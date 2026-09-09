#import "ECLBoot.h"

#import <ecl/ecl.h>

/* Generated per build. The modules header declares init functions taking a
   cl_object, so it must come after <ecl/ecl.h> and may not be included by any
   file that also sees UIKit. See WRITE-BUILD-HEADER in link.lisp. */
#import "ios-app-build.h"
#import "ios-app-modules.h"

#pragma mark - Strings

/* ECL strings are sequences of code points, so both directions go through
   UTF-32 rather than assuming the contents are ASCII. */

static NSString *StringFromLisp(cl_object s)
{
  if (s == OBJNULL || !ECL_STRINGP(s)) {
    return @"";
  }
  cl_fixnum length = ecl_length(s);
  if (length <= 0) {
    return @"";
  }
  uint32_t *points = malloc(sizeof(uint32_t) * (size_t)length);
  for (cl_fixnum i = 0; i < length; i++) {
    points[i] = (uint32_t)ecl_char(s, (cl_index)i);
  }
  NSString *result = [[NSString alloc] initWithBytes:points
                                              length:(NSUInteger)length * sizeof(uint32_t)
                                            encoding:NSUTF32LittleEndianStringEncoding];
  free(points);
  return result ?: @"";
}

static cl_object StringToLisp(NSString *s)
{
  NSData *utf32 = [s dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
  const uint32_t *points = (const uint32_t *)utf32.bytes;
  cl_index length = (cl_index)(utf32.length / sizeof(uint32_t));
  cl_object result = ecl_alloc_simple_extended_string(length);
  for (cl_index i = 0; i < length; i++) {
    ecl_char_set(result, i, (ecl_character)points[i]);
  }
  return result;
}

#pragma mark - Boot

@implementation ECLBoot

/* ------------------------------------------------------------------
 * The main-thread bridge.
 *
 * UIKit is main-thread only, and a remote REPL evaluates on a slynk worker.
 * IOS-APP-RUNTIME::ON-MAIN routes through here so that `(make-instance
 * 'my-view)' typed at a SLY prompt runs where UIKit requires rather than
 * wherever the REPL happens to be.
 *
 * Installed over the Lisp fallback in runtime.lisp, which just funcalls --
 * that fallback is what lets the same code run under the test suite on a Mac
 * with no application around it. */

static cl_object OnMainCall(cl_object thunk)
{
  /* cl_funcall rather than si_safe_eval on a constructed form: ECL's evaluator
     will not accept a literal function object as an argument, so
     (FUNCALL '#<bytecompiled-function>) fails with

       FUNCTION: Not a valid argument

     before the thunk is ever called -- and si_safe_eval swallows that into its
     error value, so the bridge silently returns NIL. ON-MAIN wraps what it
     passes here in a HANDLER-CASE, which is the better place for it anyway:
     the condition is then re-signalled on the thread that asked, rather than
     on the main thread where nobody is listening. */
  if (NSThread.isMainThread) {
    /* dispatch_sync to the main queue from the main thread deadlocks. */
    return cl_funcall(1, thunk);
  }

  /* Stack storage, so the collector can see it: dispatch_sync runs the block
     inline and never copies it to the heap. */
  __block cl_object result = ECL_NIL;
  dispatch_sync(dispatch_get_main_queue(), ^{
    result = cl_funcall(1, thunk);
  });
  return result;
}

+ (void)boot
{
  static BOOL booted = NO;
  if (booted) {
    return;
  }
  booted = YES;

  /* The bundle is read-only. Point HOME at the one directory the app may write
     to, so anything in Lisp that opens a file relative to ~ lands there. */
  NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                            NSUserDomainMask,
                                                            YES).firstObject;
  setenv("HOME", documents.fileSystemRepresentation, 1);

  /* ECL installs handlers for these so it can turn them into Lisp conditions.
     On iOS that fights the system and the debugger, and a Lisp stack overflow
     becoming a crash rather than a condition is the right trade here. */
  ecl_set_option(ECL_OPT_TRAP_SIGSEGV, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGFPE, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGINT, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGILL, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGBUS, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGPIPE, 0);
  ecl_set_option(ECL_OPT_TRAP_INTERRUPT_SIGNAL, 0);
  ecl_set_option(ECL_OPT_SIGNAL_HANDLING_THREAD, 0);

  /* static: cl_boot keeps this pointer rather than copying, and SI:ARGV reads
     through it whenever anything asks for EXT:COMMAND-ARGS -- which
     SLYNK:CONNECTION-INFO does, on the first message of every REPL session. On
     the stack it is reclaimed the moment +boot returns, and the crash is a
     SIGSEGV in strlen a long way from here. */
  static char *argv[] = { (char *)IOS_APP_NAME, NULL };
  cl_boot(1, argv);

  /* There is no C compiler on the phone, so COMPILE has to go through the
     bytecodes compiler. Without this, anything that compiles a function --
     including parts of CLOS -- fails. It is also what keeps the image live:
     DEFUN and DEFCLASS at runtime work because of this line. */
  si_safe_eval(3, ecl_read_from_cstring("(ext:install-bytecodes-compiler)"),
               ECL_NIL, ECL_NIL);

  /* Declare every linked module present BEFORE initialising any of them.
     A module's own load-time code may REQUIRE another, and REQUIRE otherwise
     goes looking for a .fas under the ECLDIR compiled into this build -- which
     in the simulator is a real, readable directory on the Mac, so it finds the
     host's fasl and dies interpreting its CLINES forms. */
#define PUSH_MODULE(name, init) \
  si_safe_eval(3, ecl_read_from_cstring("(pushnew \"" name "\" *modules* :test #'equal)"), \
               ECL_NIL, ECL_NIL);
  IOS_APP_MODULES(PUSH_MODULE)
#undef PUSH_MODULE

#define INIT_MODULE(name, init) ecl_init_module(NULL, init);
  IOS_APP_MODULES(INIT_MODULE)
#undef INIT_MODULE

  /* Now that the runtime library's module has run, the package exists and
     the hook can be given its real value.

     A variable rather than a function definition because ECL compiles a call
     to a function defined in the same file as a direct C call: redefining
     %ON-MAIN-CALL would leave ON-MAIN calling the old one, silently, and the
     symptom is a bridge that appears to work while running on the wrong
     thread. */
  ecl_setq(ecl_process_env(),
           ecl_make_symbol("*ON-MAIN-HOOK*", "IOS-APP-RUNTIME"),
           ecl_make_cfun((cl_objectfn_fixed)OnMainCall,
                         ecl_make_symbol("%ON-MAIN-CALL", "IOS-APP-RUNTIME"),
                         ECL_NIL, 1));

  /* Where the bundled resources are, for Lisp that wants to LOAD one. */
  ecl_setq(ecl_process_env(),
           ecl_make_symbol("*BUNDLE-PATH*", "CL-USER"),
           StringToLisp([NSBundle.mainBundle.resourcePath
                          stringByAppendingString:@"/"]));

  /* Everything build-specific is a string in the generated header, and all the
     boot LOGIC is Lisp, in the runtime package, where it can be tested on the
     host rather than only on a phone. */
  si_safe_eval(3, ecl_read_from_cstring(IOS_APP_BOOT_FORM), ECL_NIL, ECL_NIL);
}

+ (NSString *)evaluate:(NSString *)source
{
  cl_object quote = ecl_make_symbol("QUOTE", "COMMON-LISP");
  cl_object helper = ecl_make_symbol("EVALUATE-TO-STRING", "IOS-APP-RUNTIME");
  cl_object form = cl_list(2, helper, cl_list(2, quote, StringToLisp(source)));
  cl_object result = si_safe_eval(3, form, ECL_NIL, ECL_NIL);
  if (result == ECL_NIL) {
    return @"; the evaluator failed";
  }
  return StringFromLisp(result);
}

+ (void)evaluateOnMain:(NSString *)source
{
  if (NSThread.isMainThread) {
    /* dispatch_sync to the main queue from the main thread deadlocks. */
    (void)[self evaluate:source];
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    (void)[self evaluate:source];
  });
}

@end
