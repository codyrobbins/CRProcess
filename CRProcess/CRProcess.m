#import <sys/sysctl.h>
#import "CRProcess.h"

@interface CRProcess ()

+ (CRProcess *)processWithId:(NSNumber *)id;
- (CRProcess *)initWithId:(NSNumber *)id;
- (void)getProcessInfo;

@end

@implementation CRProcess

+ (NSArray *)processes
{
  bool failed;
	int requestedInformation[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
  size_t bufferSize;
  NSMutableData *data;
  struct kinfo_proc *process;
  unsigned long processCount;
  NSMutableArray *processes;

  failed = sysctl(requestedInformation, 3, NULL, &bufferSize, NULL, 0);

  if (failed)
    return(@[]);

  data = [NSMutableData dataWithCapacity:bufferSize];

  failed = sysctl(requestedInformation, 3, data.mutableBytes, &bufferSize, NULL, 0);

  if (failed)
    return(@[]);

  processes = [NSMutableArray new];
  process = data.mutableBytes;
  processCount = bufferSize / sizeof(struct kinfo_proc);

  for (int i = 0; i < processCount; ++i, ++process)
  {
    pid_t pid = process->kp_proc.p_pid;
    [processes addObject:[CRProcess processWithId:[NSNumber numberWithInt:pid]]];
  }

  return(processes);
}

+ (CRProcess *)processWithId:(NSNumber *)id
{
  return([[self alloc] initWithId:id]);
}

- (CRProcess *)initWithId:(NSNumber *)id
{
  if (self = [self init]) {
    _id = id;
    [self getProcessInfo];
  }

  return(self);
}

- (void)getProcessInfo
{
  _executablePath = @"EXECUTABLE_NAME";
  _arguments = @[@"ARGUMENT"];
  _environmentVariables = @{@"ENVIRONMENT_NAME": @"ENVIRONMENT_VALUE"};

  NSMutableArray *arguments = [NSMutableArray new];
  NSMutableDictionary *environmentVariables = [NSMutableDictionary new];
  NSArray *environmentVariable;

  char *real_command_name;
  int real_argvlen = 0;
  int real_argv0len = 0;
  bool show_args = true;

  char *marker;
  int capacity;
  NSMutableData *data;

  char **command_name = &real_command_name;
  int *argvlen = &real_argvlen;
  int *argv0len = &real_argv0len;

  /***/

  int		mib[3], argmax, nargs, c = 0;
	size_t		size;
	char		*procargs, *sp, *np, *cp;
	extern int	eflg;

	/* Get the maximum process arguments size. */
	mib[0] = CTL_KERN;
	mib[1] = KERN_ARGMAX;

  // Get the maximum number of bytes worth of command line arguments that the kernel allows an executable to receive. The `sysctl` call writes this value into `argmax` and we tell it that it has an integer's worth of memory to write into (that is, four bytes).
	size = sizeof(argmax);
	if (sysctl(mib, 2, &argmax, &size, NULL, 0) == -1) {
		goto ERROR_A;
	}

  // Allocate enough memory to store the maximum number of bytes worth of command line arguments that we can possibly run into. The pointer `procargs` will point to the start of this memory region we've allocated for this data.

	/* Allocate space for the arguments. */
	procargs = (char *)malloc(argmax);
	if (procargs == NULL) {
		goto ERROR_A;
	}

	/*
	 * Make a sysctl() call to get the raw argument space of the process.
	 * The layout is documented in start.s, which is part of the Csu
	 * project.  In summary, it looks like:
	 *
	 * /---------------\ 0x00000000
	 * :               :
	 * :               :
	 * |---------------|
	 * | argc          |
	 * |---------------|
	 * | arg[0]        |
	 * |---------------|
	 * :               :
	 * :               :
	 * |---------------|
	 * | arg[argc - 1] |
	 * |---------------|
	 * | 0             |
	 * |---------------|
	 * | env[0]        |
	 * |---------------|
	 * :               :
	 * :               :
	 * |---------------|
	 * | env[n]        |
	 * |---------------|
	 * | 0             |
	 * |---------------| <-- Beginning of data returned by sysctl() is here.
	 * | argc          |
	 * |---------------|
	 * | exec_path     |
	 * |:::::::::::::::|
	 * |               |
	 * | String area.  |
	 * |               |
	 * |---------------| <-- Top of stack.
	 * :               :
	 * :               :
	 * \---------------/ 0xffffffff
	 */
	mib[0] = CTL_KERN;
	mib[1] = KERN_PROCARGS2;
	mib[2] = [self.id intValue];

  // Get the entire raw argument space of this process, including the command line arguments and environment variables. The `sysctl` call writes this data into `procargs` and we tell it that it has an amount of memory available to write into that is equal to the maximum number of bytes worth of command line arguments that we previously figured out (`argmax`). The `sysctl` call will also write into `size` the number of bytes of data it has written into `procargs`.
	size = (size_t)argmax;
	if (sysctl(mib, 3, procargs, &size, NULL, 0) == -1) {
		goto ERROR_B;
	}

  // The very first value in the raw argument space is an integer value representing the number of command line arguments (i.e., `argc`). We use `memcpy` to copy this value out of `procargs` and directly into `nargs`, telling it to copy an integer's worth of bytes (that is, four bytes).
	memcpy(&nargs, procargs, sizeof(nargs));

  // Set the pointer `cp` to the start of the memory location pointed to by `procargs`, and then advance it an integer's worth of bytes (that is, four bytes) to move it past `argc` to the executable path. The executable path is a special Apple kernel-specific argument provided to the `main` function of C programs that contains the actual path to the executable which the kernel started executing code from when it was given the system call to run executable code. A program's `argv[0]` is usually the name of the executable, but it may contain a relative path or a shell alias; furthermore, programs can change the value of `argv[0]`. So, the executable path argument is an additional argument that Apple uses internally that always contains the full executable path.
	cp = procargs + sizeof(nargs);

  /***/
  marker = cp;
  /***/

  // We next skip over the executable path because `ps` isn't interested in it. We know that `procargs` contains a quantity of bytes equal to `size`. So, this advances the `cp` pointer a byte at a time until we get to the end of the data pointed to by `procargs` or we hit a null byte. The null byte indicates the end of the null-terminated executable path string. The loop condition `&procargs[size]` uses array syntax to advance the `procargs` pointer by `size` bytes—that is, to the end of procargs. The reference operator then gets the memory address of that location—i.e., the end of `procargs`. So, we advance `cp` until we hit the end of `procargs`.

	/* Skip the saved exec_path. */
	for (; cp < &procargs[size]; cp++) {
		if (*cp == '\0') {
			/* End of exec_path reached. */
			break;
		}
	}

  /***/
  capacity = cp - marker;
  data = [NSMutableData dataWithCapacity:capacity];

  memcpy(data.mutableBytes, marker, capacity);

  _executablePath = [NSString stringWithCString:data.mutableBytes encoding:NSASCIIStringEncoding];
  /***/

  // If we have reached the end of `procargs`, we're done here—just skip to the end of the function.
	if (cp == &procargs[size]) {
		goto ERROR_B;
	}

  // Similar to above, keep advancing `cp` until we hit a non-null byte. The null-terminated executable path string may have additional trailing null bytes. Keep advancing until we hit the first byte of `argv`.

	/* Skip trailing '\0' characters. */
	for (; cp < &procargs[size]; cp++) {
		if (*cp != '\0') {
			/* Beginning of first argument reached. */
			break;
		}
	}

  // Again, if we've reached the end of `procargs` there's nothing left to do.
	if (cp == &procargs[size]) {
		goto ERROR_B;
	}

  // The `sp` pointer is used to point to the start of `argv`. Think of `sp` as "string pointer" (for the start of the command string), `cp` for "character pointer" (for the current character we're at), and `np` for "null pointer" (for the location of the null byte at the end of the command string.

	/* Save where the argv[0] string starts. */
	sp = cp;

  /***/
  marker = cp;
  /***/

  // Here's where we get all the arguments (i.e., `argv`). Initialize the null pointer `np` to `NULL` to start, and then loop until either: we get to the end of `procargs`, like in the loops above; or we have processed a number of command line arguments equal to the number the program has, as we determined above and stored in `nargs`. The variable `c` here is the counter of which argument we're currently on. Every time we hit a null byte, we have hit the end of a null-terminated string representing an argument. The first time we hit a null byte we: increment the argument counter `c`; save the length of the first argument into `argv0len` by simply calculating the distance between the current character and the start of `argv`; and save the location of the current null byte to `np`. For any subsequent bytes, we turn the previous null byte into a space so we get a command-line style representation of the command string with arguments.

	/*
	 * Iterate through the '\0'-terminated strings and convert '\0' to ' '
	 * until a string is found that has a '=' character in it (or there are
	 * no more strings in procargs).  There is no way to deterministically
	 * know where the command arguments end and the environment strings
	 * start, which is why the '=' character is searched for as a heuristic.
	 */
	for (np = NULL; c < nargs && cp < &procargs[size]; cp++) {
		if (*cp == '\0') {

      /***/
      capacity = cp - marker;
      data = [NSMutableData dataWithCapacity:capacity];

      memcpy(data.mutableBytes, marker, capacity);

      [arguments addObject:[NSString stringWithCString:data.mutableBytes encoding:NSASCIIStringEncoding]];

      marker = cp + 1;
      /***/

			c++;
			if (np != NULL) {
        /* Convert previous '\0'. */
        *np = ' ';
			} else {
        *argv0len = cp - sp;
			}
			/* Note location of current '\0'. */
			np = cp;

			if (!show_args) {
        /*
         * Don't convert '\0' characters to ' '.
         * However, we needed to know that the
         * command name was terminated, which we
         * now know.
         */
        break;
			}
		}
	}

  /***/
  _arguments = arguments;
  /***/

	/*
	 * If eflg is non-zero, continue converting '\0' characters to ' '
	 * characters until no more strings that look like environment settings
	 * follow.
	 */
  //	if ( show_args && (eflg != 0) && ( (getuid() == 0) || (KI_EPROC(k)->e_pcred.p_ruid == getuid()) ) ) {
  for (; cp < &procargs[size]; cp++) {
    if (*cp == '\0') {
      if (np != NULL) {
        if (&np[1] == cp) {
          /*
           * Two '\0' characters in a row.
           * This should normally only
           * happen after all the strings
           * have been seen, but in any
           * case, stop parsing.
           */
          break;
        }
        /* Convert previous '\0'. */
        //        *np = ' ';
      }

      /***/
      capacity = cp - marker;
      data = [NSMutableData dataWithCapacity:capacity];

      memcpy(data.mutableBytes, marker, capacity);

      environmentVariable = [[NSString stringWithCString:data.mutableBytes encoding:NSASCIIStringEncoding] componentsSeparatedByString:@"="];

      if (environmentVariable.count > 0) {
        if (environmentVariable.count > 1)
          [environmentVariables setObject:environmentVariable[1] forKey:environmentVariable[0]];
        else
          [environmentVariables setObject:@"" forKey:environmentVariable[0]];
      }

      marker = cp + 1;
      /***/

      /* Note location of current '\0'. */
      np = cp;
    }
  }
  //	}

  /***/
  _environmentVariables = environmentVariables;
  /***/

	/*
	 * sp points to the beginning of the arguments/environment string, and
	 * np should point to the '\0' terminator for the string.
	 */
	if (np == NULL || np == sp) {
		/* Empty or unterminated string. */
		goto ERROR_B;
	}

	/* Make a copy of the string. */
	*argvlen = asprintf(command_name, "%s", sp);

	/* Clean up. */
	free(procargs);
	return;

ERROR_B:
  //  printf("%i", KI_PROC(k)->p_pid);
	free(procargs);
ERROR_A:
  //  printf("%i", KI_PROC(k)->p_pid);
  //  printf(": Error A\n");
	*argv0len = *argvlen
  = asprintf(command_name, "");
}

@end