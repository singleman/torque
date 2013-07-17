#include "license_pbs.h" /* See here for the software license */
#include "trq_auth_daemon.h"
#include <pbs_config.h>   /* the master config generated by configure */
#include <sys/stat.h> /* umask */

#include <stdlib.h> /* calloc, free */
#include <stdio.h> /* printf */
#include <string.h> /* strcat */
#include <pthread.h> /* threading functions */
#include <errno.h> /* errno */
#include <syslog.h> /* openlog and syslog */
#include <unistd.h> /* getgid, fork */
#include <grp.h> /* setgroups */
#include <ctype.h> /*isspace */
#include <getopt.h> /*getopt_long */
#include "pbs_error.h" /* PBSE_NONE */
#include "pbs_constants.h" /* AUTH_IP */
#include "pbs_ifl.h" /* pbs_default, PBS_BATCH_SERVICE_PORT, TRQ_AUTHD_SERVICE_PORT */
#include "net_connect.h" /* TRQAUTHD_SOCK_NAME */
#include "../lib/Libnet/lib_net.h" /* start_listener */
#include "../lib/Libifl/lib_ifl.h" /* process_svr_conn */
#include "../lib/Liblog/chk_file_sec.h" /* IamRoot */
#include "../lib/Liblog/pbs_log.h" /* logging stuff */
#include "../include/log.h"  /* log events and event classes */
#include "csv.h" /*csv_nth() */


#define MAX_BUF 1024
#define TRQ_LOGFILES "client_logs"

extern char *msg_daemonname;
extern pthread_mutex_t *log_mutex;
extern pthread_mutex_t *job_log_mutex;

extern int debug_mode;
static int changed_msg_daem = 0;
static char *active_pbs_server;

int load_config(
    char **ip,
    int *t_port,
    int *d_port)
  {
  int rc = PBSE_NONE;
  char *tmp_name = pbs_default();
  /* Assume TORQUE_HOME = /var/spool/torque */
  /* /var/spool/torque/server_name */
  if (tmp_name == NULL)
    rc = PBSE_BADHOST;
  else
    {
    /* Currently this only display's the port for the trq server
     * from the lib_ifl.h file or server_name file (The same way
     * the client utilities determine the pbs_server port)
     */
    printf("hostname: %s\n", tmp_name);
    *ip = tmp_name;
    PBS_get_server(tmp_name, (unsigned int *)t_port);
    if (*t_port == 0)
      *t_port = PBS_BATCH_SERVICE_PORT;
    *d_port = TRQ_AUTHD_SERVICE_PORT;
    set_active_pbs_server(tmp_name);
    }
  return rc;
  }

int load_ssh_key(
    char **ssh_key)
  {
  int rc = PBSE_NONE;
  return rc;
  }



void initialize_globals_for_log(int port)
  {
  strcpy(pbs_current_user, "trqauthd");   
  if ((msg_daemonname = strdup(pbs_current_user)))
    changed_msg_daem = 1;
  log_set_hostname_sharelogging(active_pbs_server, port);
  }

void clean_log_init_mutex(void)
  {
  pthread_mutex_destroy(log_mutex);
  pthread_mutex_destroy(job_log_mutex);
  free(log_mutex);
  free(job_log_mutex);
  }

int init_trqauth_log(int server_port)
  {
  const char *path_home = PBS_SERVER_HOME;
  int eventclass = PBS_EVENTCLASS_TRQAUTHD;
  char path_log[MAXPATHLEN + 1];
  char *log_file=NULL;
  char  error_buf[MAX_BUF];
  int  rc;

  rc = log_init(NULL, NULL);
  if (rc != PBSE_NONE)
    return(rc);
  
  log_get_set_eventclass(&eventclass, SETV);

  initialize_globals_for_log(server_port);
  sprintf(path_log, "%s/%s", path_home, TRQ_LOGFILES);
  if ((mkdir(path_log, 0755) == -1) && (errno != EEXIST))
    {
       openlog("daemonize_trqauthd", LOG_PID | LOG_NOWAIT, LOG_DAEMON);
       syslog(LOG_ALERT, "Failed to create client_logs directory: %s errno: %d error message: %s", path_log, errno, strerror(errno));
       sprintf(error_buf,"Failed to create client_logs directory: %s, error message: %s",path_log,strerror(errno));
       log_err(errno,__func__,error_buf);
       closelog();
       return(PBSE_SYSTEM);
    }
    pthread_mutex_lock(log_mutex);
    rc = log_open(log_file, path_log);
    pthread_mutex_unlock(log_mutex);

    return(rc);

  }


int daemonize_trqauthd(const char *server_ip, int server_port, void *(*process_meth)(void *))
  {
  int gid;
  pid_t pid;
  int   rc;
  char  error_buf[MAX_BUF];
  char msg_trqauthddown[MAX_BUF];
  char unix_socket_name[MAXPATHLEN + 1];

  umask(022);

  gid = getgid();
  /* secure supplemental groups */
  if(setgroups(1, (gid_t *)&gid) != 0)
    {
    fprintf(stderr, "Unable to drop secondary groups. Some MAC framework is active?\n");
    snprintf(error_buf, sizeof(error_buf),
                     "setgroups(group = %lu) failed: %s\n",
                     (unsigned long)gid, strerror(errno));
    fprintf(stderr, "%s\n", error_buf);
    return(1);
    }

  if (getenv("PBSDEBUG") != NULL)
    debug_mode = TRUE;
  if (debug_mode == FALSE)
    {
    pid = fork();
    if(pid > 0)
      {
      /* parent. We are done */
      return(0);
      }
    else if (pid < 0)
      {
      /* something went wrong */
      fprintf(stderr, "fork failed. errno = %d\n", errno);
      return(PBSE_RMSYSTEM);
      }
    else
      {
      fprintf(stderr, "trqauthd daemonized - port %d\n", server_port);
      /* If I made it here I am the child */
      fclose(stdin);
      fclose(stdout);
      fclose(stderr);
      /* We closed 0 (stdin), 1 (stdout), and 2 (stderr). fopen should give us
         0, 1 and 2 in that order. this is a UNIX practice */
      if (fopen("/dev/null", "r") == NULL)
        perror(__func__);

      if (fopen("/dev/null", "r") == NULL)
        perror(__func__);

      if (fopen("/dev/null", "r") == NULL)
        perror(__func__);
      }
    }
  else
    {
    fprintf(stderr, "trqauthd port: %d\n", server_port);
    }

    /* start the listener */
    snprintf(unix_socket_name, sizeof(unix_socket_name), "%s/%s", TRQAUTHD_SOCK_DIR, TRQAUTHD_SOCK_NAME);
    rc = start_domainsocket_listener(unix_socket_name, process_meth);
    if(rc != PBSE_NONE)
      {
      openlog("daemonize_trqauthd", LOG_PID | LOG_NOWAIT, LOG_DAEMON);
      syslog(LOG_ALERT, "trqauthd could not start: %d\n", rc);
      log_err(rc, "daemonize_trqauthd", (char *)"trqauthd could not start");
      pthread_mutex_lock(log_mutex);
      log_close(1);
      pthread_mutex_unlock(log_mutex);
      if (changed_msg_daem && msg_daemonname) 
        {
          free(msg_daemonname);
        }
      clean_log_init_mutex();
      exit(-1);
      }
    snprintf(msg_trqauthddown, sizeof(msg_trqauthddown),
      "TORQUE authd daemon shut down and no longer listening on IP:port %s:%d",
      server_ip, server_port);
    log_record(PBSEVENT_SYSTEM | PBSEVENT_FORCE, PBS_EVENTCLASS_TRQAUTHD,
      msg_daemonname, msg_trqauthddown);
    pthread_mutex_lock(log_mutex);
    log_close(1);
    pthread_mutex_unlock(log_mutex);
    if (changed_msg_daem && msg_daemonname)
      {
      free(msg_daemonname);
      }
    clean_log_init_mutex();
    exit(0);
  }

void parse_command_line(int argc, char **argv)
  {
  int c;
  int option_index = 0;
  int iterator;
  static struct option long_options[] = {
            {"about",   no_argument,      0,  0 },
            {"help",    no_argument,      0,  0 },
            {"version", no_argument,      0,  0 },
            {0,         0,                0,  0 }
  };

  while ((c = getopt_long(argc, argv, "D", long_options, &option_index)) != -1)
    {
    switch (c)
      {
      case 0:
	switch (option_index)  /* One of the long options was passed */
          {
          case 0:   /*about*/
            fprintf(stderr, "torque user authorization daemon version %s\n", VERSION);
            exit(0);
            break;
          case 1:   /* help */
            iterator = 0;
            fprintf(stderr, "Usage: trqauthd [FLAGS]\n");
            while (long_options[iterator].name != 0)
              {
              fprintf(stderr, "  --%s\n", long_options[iterator++].name);
              }
            fprintf(stderr, "\n  -D // RUN IN DEBUG MODE\n");
            exit(0);
            break;
          case 2:   /* version */
            fprintf(stderr, "Version: %s Commit: %s\n", VERSION, GIT_HASH);
            exit(0);
            break;
          }
        break;

      case 'D':
        debug_mode = TRUE;
        break;

      default:
        fprintf(stderr, "Unknown command line option\n");
        exit(1);
        break;
      }
    }
  }


extern "C"
{
int trq_main(

  int    argc,
  char **argv,
  char **envp)

  {
  int rc = PBSE_NONE;
  char *the_key = NULL;
  char *sign_key = NULL;
  int trq_server_port = 0;
  int daemon_port = 0;
  void *(*process_method)(void *) = process_svr_conn;

  parse_command_line(argc, argv);

  if (IamRoot() == 0)
    {
    printf("This program must be run as root!!!\n");
    return(PBSE_IVALREQ);
    }

  if ((rc = load_config(&active_pbs_server, &trq_server_port, &daemon_port)) != PBSE_NONE)
    {
    }
  else if ((rc = load_ssh_key(&the_key)) != PBSE_NONE)
    {
    }
  else if ((rc = init_trqauth_log(daemon_port) != PBSE_NONE))
    {
    }
  else if ((rc = validate_server(active_pbs_server, trq_server_port, the_key, &sign_key)) != PBSE_NONE)
    {
    }
  else if ((rc = daemonize_trqauthd(AUTH_IP, daemon_port, process_method)) == PBSE_NONE)
    {
    }
  else
    {
    printf("Daemon exit requested\n");
    }
  if (the_key != NULL)
    free(the_key);
  return rc;
  }
}
