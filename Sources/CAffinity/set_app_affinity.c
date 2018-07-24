/*
 * Return values:
 *    0: Success
 *   -1: Unable to get list of thread ids
 *   -2: Invalid number of cores specified
 *   -3: No permission to set affinity (forgot to run as root?)
 */

#define _GNU_SOURCE
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
//#include <stdio.h>
#include <sched.h>
#include <errno.h>

#include "set_app_affinity.h"

int set_app_affinity(uint num_cores) {
  cpu_set_t cpumask;
  int result;

  if (num_cores < 1 || num_cores > CPU_SETSIZE) {
    // Invalid number of cores
    return -2;
  }
  //Restrict the app to the first num_cores cores
  //TODO: Precompute and store the possible masks for greater efficiency
  CPU_ZERO(&cpumask);
  for (int i = 0; i < num_cores; i++) {
    CPU_SET(i, &cpumask);
  }
  
  DIR *proc_dir;
  proc_dir = opendir("/proc/self/task");
  
  if (proc_dir) {
    /* /proc available, iterate through tasks... */
    struct dirent *entry;
    
    errno = 0;
    while ((entry = readdir(proc_dir)) != NULL) {
      if(entry->d_name[0] == '.') continue;
      
      pid_t tid = (pid_t)atoi(entry->d_name);
      
      // Set the affinity for this thread
      result = sched_setaffinity(tid, sizeof(cpu_set_t), &cpumask);
      
      if (result) {
	switch errno {
	  case EINVAL:
	    // Bad cpu mask, num_cores invalid?
	    return -2;
	  case EPERM:
	    // Not running as root?
	    return -3;
	  case ESRCH:
	    // thread no longer exists, just continue
	    break;
	  }
      }
    }
    
    if (errno != 0) {
      // There was an error instead of just reaching the end of the stream
      return -1;
    }
  
    closedir(proc_dir);
    
  } else {
    // /proc not available, cannot set affinity
    return -1;
  }

  return 0;
}
