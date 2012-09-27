#define _LARGEFILE64_SOURCE
#define _GNU_SOURCE
#include <features.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>

#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <inttypes.h>
#include <errno.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <time.h>

/*! Invalid file descriptor. */
#define	INVALID_FD	(-1)

/*! Memory page size. 
    Set the sysconf(_SC_PAGESIZE) value in main().
*/
long	ScPageSize=4096;

#define	DO_RANDOM_ACCESS_BOTH	(0) /* should be 0 */
#define	DO_RANDOM_ACCESS_READ	(1)
#define	DO_RANDOM_ACCESS_WRITE	(2)

#define	DO_READ_FILE_NO		(0) /* should be 0 */
#define	DO_READ_FILE_LIGHT	(1)
#define	DO_READ_FILE_STRICT	(2)

#define	DO_OPTION_NO	(0) /* should be 0 */
#define	DO_OPTION_YES	(1)

#define	DEF_FillFile	(0)
#define	DEF_DoReadFile	(0)
#define	DEF_FileSize	(0)
#define	DEF_BlockSize	(4096)
#define	DEF_BlocksMin	(256)
#define	DEF_BlocksMax	(1024)
#define	DEF_BlockStart	(0)
#define	DEF_BlockEnd	(INT64_MAX)
#define	DEF_Repeats	(1000)
#define	DEF_Seed	(0)
#define	DEF_DoRandomAccess	(DO_RANDOM_ACCESS_BOTH)
#define	DEF_DoDirect		(DO_OPTION_YES)
#define	DEF_DoDirectRandomRW	(DO_OPTION_YES)
#define	DEF_DoMark		(DO_OPTION_YES)


/*! Command line argument holder. */
typedef struct {
	off64_t			FileSize;	/*!< -f n file size. */
	off64_t			BlockSize;	/*!< -b n block size. */
	off64_t			BlocksMin;	/*!< -i n Minimum blocks to read. */
	off64_t			BlocksMax;	/*!< -a n Maximum blocks to read. */
	off64_t			BlockStart;	/*!< -o n Origin block number to test. */
	off64_t			BlockEnd;	/*!< -e n End block number to test.  */
	long			Repeats;	/*!< -n n number of repeats. */
	long			Seed;		/*!< -s n random seed number. */
	char			*PathName;	/*!< Device or file path name to test. */
	int			FillFile;	/*!< Sequential Fill work file. */
	int			DoReadFile;	/*!< Sequential Read work file. */
	int			DoRandomAccess;	/*!< Do Random access Both r/w, Read only, Write only. */
	int			DoDirect;	/*!< Do O_DIRECT io */
	int			DoDirectRandomRW; /*!< Do O_DIRECT io at random read/write. */
	int			DoMark;		  /*!< Do Block Marking. */
} TCommandLineOption;


TCommandLineOption	CommandLine={
	.PathName="",
	.FileSize=DEF_FileSize,
	.BlockSize=DEF_BlockSize,
	.BlocksMin=DEF_BlocksMin,
	.BlocksMax=DEF_BlocksMax,
	.BlockStart=DEF_BlockStart,
	.BlockEnd=DEF_BlockEnd,
	.Repeats=DEF_Repeats,
	.Seed=DEF_Seed,
	.FillFile=DEF_FillFile,
	.DoReadFile=DEF_DoReadFile,
	.DoRandomAccess=DEF_DoRandomAccess,
	.DoDirect=DEF_DoDirect,
	.DoDirectRandomRW=DEF_DoDirectRandomRW,
	.DoMark=DEF_DoMark
};

/*! Accumulate numbers from touched memory. */
uint64_t	TouchSums=0;

/*! Store milli second to timespec.
    @param ts point timespec to store.
    @param msec time in milli second.
*/
void timespecLoadMilliSec(struct timespec *ts, long msec)
{	ldiv_t		sec_milli;

	sec_milli=ldiv(msec,1000);
	sec_milli.rem*=1000L*1000L;	/* milli to micro to nano. */
	ts->tv_sec= sec_milli.quot;
	ts->tv_nsec=sec_milli.rem;
}

/*! Convert timespec to double.
    @param ts points timespec structure.
    @return double second.
*/
double timespecToDouble(const struct timespec *ts)
{	return((double)(ts->tv_sec)+(ts->tv_nsec)/(1000.0*1000.0*1000.0));
}

/*! Sub timespecs. *y=*a-*b.
    @param y point timespec structure to store *a-*b
    @param a point timespec structure.
    @param b point timespec structure.
    @return struct timespec pointer equal to y.
    @note *a means end time, *b means start time.
*/
struct timespec *timespecSub(struct timespec *y, const struct timespec *a, const struct timespec *b)
{	time_t	sec;
	long	nsec;

	sec= a->tv_sec- b->tv_sec;
	nsec=a->tv_nsec-b->tv_nsec;
	if (nsec<0) {
		/* borrow */
		sec--;
		nsec+=1000L*1000L*1000L;
	}
	y->tv_sec=sec;
	y->tv_nsec=nsec;
	return(y);
}

/*! Add timespecs. *y=*a+*b.
    @param y point timespec structure to store *a+*b
    @param a point timespec structure.
    @param b point timespec structure.
    @return struct timespec pointer equal to y.
*/
struct timespec *timespecAdd(struct timespec *y, const struct timespec *a, const struct timespec *b)
{	time_t	sec;
	long	nsec;

	sec=  a->tv_sec+ b->tv_sec;
	nsec= a->tv_nsec+b->tv_nsec;

	if (nsec>=1000L*1000L*1000L) {
		/* Carry. */
		sec++;
		nsec-=1000L*1000L*1000L;
	}
	y->tv_sec=sec;
	y->tv_nsec=nsec;
	return(y);
}

/*! Round up.
    @param a  value to round up.
    @param by round step value.
    @return long long rounded value.
*/
long long RoundUpBy(long long a, long long by)
{	if (by==0) {
		/* avoid zero divide. */
		return(a);
	}
	return(((a+by-1)/by)*by);
}

/*! string to long with suffix.
    @param p  point char array to parse unsigned long number.
    @param p2 point char* to store pointer at stopping parse.
    @param radix default radix to parse.
    @return unsigned long parsed number.
*/
unsigned long long strtoulkmg(char *p, char **p2, int radix)
{	unsigned long long	a;
	char			*ptmp;
	char			*dummy;

	if (!p2) {
		p2=&dummy;
	}

	if (!p) {
		*p2=p;
		return(0);
	}
	ptmp="";
	a=strtoul(p,&ptmp,radix);
	if (p==ptmp) {
		*p2=p;
		return(0);
	}
	p=ptmp;
	switch (*p) {
		case 'k': 
		case 'K': {
			/* kilo */
			p++;
			a*=1024ULL;
			break;
		}
		
		case 'm': 
		case 'M': {
			/* Mega */
			p++;
			a*=1024ULL*1024ULL;
			break;
		}

		case 'g': 
		case 'G': {
			/* Giga */
			p++;
			a*=1024ULL*1024ULL*1024ULL;
			break;
		}

		case 't': 
		case 'T': {
			/* Tera */
			p++;
			a*=1024ULL*1024ULL*1024ULL*1024ULL;
			break;
		}
	}
	*p2=p;
	return(a);
}

/*! long long to signed hex string
    @param buf point char buffer to store hex string.
    @param a long long value to convert signed hex.
    @return char* equal to buf.
    @note format is +0x0123456789abcdef
*/
char *LLToHexStr(char *buf, long long a)
{	char	sgn;
	if (a>=0) {
		sgn='+';
	} else {
		sgn='-';
		a=-a;
	}
	sprintf(buf,"%c0x%.16llx",sgn,a);
	return(buf);
}

/*! Set O_DIRECT file descriptor flag.
    @param fd file descriptor to set O_DIRECT flag.
    @param o_direct 0: Clear O_DIRECT(Kernel buffered), 1: Set O_DIRECT(Kernel unbuffered).
    @return int 0: Failed, 1: Success.
*/
int SetFdODirect(int fd, int o_direct)
{	long	flags;

	flags=fcntl(fd,F_GETFD);
	if (flags<0) {
		printf("fd(%d): Error: F_GETFD failed. %s(%d)\n",fd,strerror(errno),errno);
		return 0 /* Failed. */;
	}
	if (o_direct) {
		/* Set O_DIRECT. */
		flags|=O_DIRECT;
	} else {
		/* Clear O_DIRECT. */
		flags&=~O_DIRECT;
	}
	if (fcntl(fd,F_SETFD,flags)!=0) {
		printf("fd(%d): Error: F_SETFD failed. %s(%d)\n",fd,strerror(errno),errno);
		return 0 /* Failed. */;
	}
	return 1 /* Success. */;
}

#define TRY_WRITE_MAX	(1000)

/*! Try write.
    Continue write, until all requested bytes are written.
    @param fd  file descriptor to write bytes.
    @param b   points byte array to write.
    @param len bytes to write.
    @param done points int variable to store success(!=0) or failed(==0).
    @return ssize_t written bytes.
*/
ssize_t TryWrite(int fd, const char *b, size_t len, int *done)
{	ssize_t		wresult;
	ssize_t		remain;
	int		trycount;
	int		done_dummy;
	
	if (!done) {
		/* Need dummy. */
		done=&done_dummy;
	}
	*done=1; /* True: means all bytes are written. */
	trycount=0;
	remain=len;
	while ((remain>0) && (trycount<TRY_WRITE_MAX)) {
		wresult=write(fd,b,len);
		if (wresult<0) {
			/* Error. */
			*done=0; /* False: means failed system call. */
			return(wresult);
		}
		remain-=wresult;
		if ((remain>0) && (wresult<=ScPageSize)) {
			/* Too small progress. */
			struct timespec ts_req;
			/* yeld other thread. */
			ts_req.tv_sec=0;
			ts_req.tv_nsec=1;
			nanosleep(&ts_req, NULL);
		}
		b+=wresult;
		trycount++;
	}
	return(((ssize_t)len)-remain);
}

#define TRY_READ_MAX	(1000)

/*! Try read.
    Continue read, until all requested bytes are read or EOF.
    @param fd  file descriptor to read bytes.
    @param b   points byte array to store reads.
    @param len bytes to read.
    @param done points int variable to store success(!=0) or failed(==0).
    @return ssize_t read bytes.
*/
ssize_t TryRead(int fd, char *b, size_t len, int *done)
{	ssize_t		rresult;
	ssize_t		remain;
	int		trycount;
	int		done_dummy;

	if (!done) {
		/* Need dummy. */
		done=&done_dummy;
	}
	*done=1; /* True: means all bytes are written. */
	trycount=0;
	remain=len;
	while ((remain>0) && (trycount<TRY_WRITE_MAX)) {
		rresult=read(fd,b,len);
		if (rresult<0) {
			/* Error. */
			*done=0; /* failed. */
			return(rresult);
		}
		if (rresult==0) {
			/* Eof. (success) */
			return(((ssize_t)len)-remain);
		}
		remain-=rresult;
		if ((remain>0) && (rresult<=ScPageSize)) {
			/* Too small progress. */
			struct timespec ts_req;
			/* yeld other thread. */
			ts_req.tv_sec=0;
			ts_req.tv_nsec=1;
			nanosleep(&ts_req, NULL);
		}
		b+=rresult;
		trycount++;
	}
	return(((ssize_t)len)-remain);
}

/*! Dump bytes per line. Should be power of 2. */
#define DUMP_BYTES_LINE	(0x10)

/*! Dump memory image.
    @param buf    point memory to HEX dump.
    @param n      number of bytes to dump.
    @param offset meaning offset address pointed by buf.
    @return unsigned char* argument buf + n.
*/
char *DumpMemory(char *buf, long long n, long long offset)
{	int	cntr;

	printf("%.16llx ",offset&((~0LL)-(DUMP_BYTES_LINE-1)));
	cntr=((int)offset)&(DUMP_BYTES_LINE-1);
	while (cntr>0) {
		/* Fill upto offset to start dump. */
		printf("-- ");
		cntr--;
	}

	cntr=((int)offset)&(DUMP_BYTES_LINE-1);
	while (n>0) {
		printf("%.2x",*((unsigned char*)buf));
		/* Loop until all bytes are dumped. */
		cntr++;
		n--;
		/* Step next offset. */
		offset++;
		if (cntr>=DUMP_BYTES_LINE) {
			/* End of colums. */
			if (n>0) {
				/* More dump lines. */
				printf("\n%.16llx ",offset);
			} else {
				/* No more dump lines. */
				printf("\n");
			}
			cntr=0;
		} else {
			/* Continue colums. */
			if (n>0) {
				/* Will be continue. */
				printf(" ");
			} else {
				/* End of dump. */
				printf("\n");
			}
			
		}
		/* Step next byte. */
		buf++;
	}
	return(buf);
}


/*! Parse command line arguments.
    @param opt points TCommandLineOption structure to store parsed values.
    @param argc  the argc value same as main() function's argc.
    @param argv0 the argv value same as main() function's argv.
    @return int 1: Success, 0: Failed (found invalid argument).
*/
int TCommandLineOptionParseArgs(TCommandLineOption *opt, char argc, char **argv0)
{	char	*p;
	char	*p2;
	int	c;
	int	result;
	int	opt_e;

	result=1;
	while ((c=getopt(argc,argv0,"b:f:p:r:x:d:m:i:a:o:e:n:s:h"))!=-1) {
		switch (c) {
			case 'b': { /* -b block_size */
				const char error_message[]="-b: Error: Need block size by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					off64_t	save;
					save=opt->BlockSize;
					opt->BlockSize=strtoulkmg(p,&p2,0);
					if (opt->BlockSize<=0) {
						/* Zero or negative BlockSize. */
						opt->BlockSize=save;
					}
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'f': { /* -f file_size */
				const char error_message[]="-f: Error: Need file size by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					opt->FileSize=strtoulkmg(p,&p2,0);
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'p': { /* -p sequential pre fill. */
				const char error_message[]="-p: Error: Need sequential pre fill parameter by y|n\n";
				p=optarg;
				if (p) {
					switch (*p) {
						case 'y':
							/* Do fill file. */
							opt->FillFile=1;
							break;
						case 'n':
							/* Do truncate file. */
							opt->FillFile=0;
							break;
						default:
							/* invalid. */
							printf(error_message);
							result=0;
							break;
					}
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'r': { /* -r do sequential read file. */
				const char error_message[]="-r: Error: Need sequential read parameter by y|n\n";
				p=optarg;
				if (p) {
					switch (*p) {
						case 's':
							/* Do read file. */
							opt->DoReadFile=DO_READ_FILE_STRICT;
							break;
						case 'y':
							/* Do read file. */
							opt->DoReadFile=DO_READ_FILE_LIGHT;
							break;
						case 'n':
							/* Do read file. */
							opt->DoReadFile=DO_READ_FILE_NO;
							break;
						default:
							/* invalid. */
							printf(error_message);
							result=0;
							break;
					}
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'x': { /* -x do random access. */
				const char error_message[]="-x: Error: Need random access parameter by b|r|w\n";
				p=optarg;
				if (p) {
					switch (*p) {
						case 'b':
							/* Both read and write. */
							opt->DoRandomAccess=DO_RANDOM_ACCESS_BOTH;
							break;
						case 'r':
							/* Read only. */
							opt->DoRandomAccess=DO_RANDOM_ACCESS_READ;
							break;
						case 'w':
							/* Write only. */
							opt->DoRandomAccess=DO_RANDOM_ACCESS_WRITE;
							break;
						default:
							/* invalid. */
							printf(error_message);
							result=0;
							break;
					}
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'd': { /* -d with O_DIRECT. */
				const char error_message[]="-d: Error: Need O_DIRECT parameter value by {y|n|Y|N}....\n";
				p=optarg;
				if (p) {
					while (*p) {
						switch (*p) {
							case 'y': {
								/* sequential read and write with O_DIRECT. */
								opt->DoDirect=DO_OPTION_YES;
								break;
							}
							case 'n': {
								/* sequential read and write without O_DIRECT. */
								opt->DoDirect=DO_OPTION_NO;
								break;
							}
							case 'Y': {
								/* random read and write with O_DIRECT. */
								opt->DoDirectRandomRW=DO_OPTION_YES;
								break;
							}
							case 'N': {
								/* random read and write without O_DIRECT. */
								opt->DoDirectRandomRW=DO_OPTION_NO;
								break;
							}
							default: {
								/* invalid. */
								printf(error_message);
								result=0;
								break;
							}
						}
						p++;
					}
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'm': { /* -m Do Block Number Marking. */
				const char error_message[]="-m: Error: Need do block marking parameter by y|n\n";
				p=optarg;
				if (p) {
					switch (*p) {
						case 'y': {
							/* Do block number marking. */
							opt->DoMark=DO_OPTION_YES;
							break;
						}
						case 'n': {
							/* Do not block number marking. */
							opt->DoMark=DO_OPTION_NO;
							break;
						}
						default: {
							/* invalid. */
							printf(error_message);
							result=0;
							break;
						}
					}
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'i': { /* -i blocks min. */
				const char error_message[]="-i: Error: Need random read/write blocks min by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					opt->BlocksMin=strtoulkmg(p,&p2,0);
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'a': { /* -a blocks max. */
				const char error_message[]="-a: Error: Need random read/write blocks max by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					opt->BlocksMax=strtoulkmg(p,&p2,0);
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'o': { /* -o origin block. (start block). */
				const char error_message[]="-o: Error: Need origin block by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					opt->BlockStart=strtoulkmg(p,&p2,0);
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'e': { /* -e end block. */
				const char error_message[]="-e: Error: Need end block by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					opt->BlockEnd=strtoulkmg(p,&p2,0);
					opt_e=1;
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'n': { /* -n repeat counts. */
				const char error_message[]="-n: Error: Need repeat counts by number\n";
				p=optarg;
				if (p) {
					opt->Repeats=strtol(p,&p2,0);
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 's': { /* -s random seed number. */
				const char error_message[]="-s: Error: Need random seed by number.\n";
				p=optarg;
				if (p) {
					opt->Seed=strtol(p,&p2,0);
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'h': { /* -h show help. */
				printf("%s: Info: Show help.\n",*argv0);
				result=0;
				break;
			}
			default: { /* unknown. */
				if (optind>0) {
					printf("%s: Error: Invalid option, show help.\n",argv0[optind-1]);
				} else {
					printf("%s: Error: May command line parse error, show help.\n",*argv0);
				}
				result=0;
				break;
			}
		}
	}
	if (optind>=argc) {
		printf("%s: Error: Need path name to read/write test.\n",*argv0);
		result=0;
	} else {
		opt->PathName=argv0[optind];
	}

	if (opt->BlocksMin>opt->BlocksMax) {
		/* Blocks Min-Max upside down. */
		off64_t		tmp;
		tmp=opt->BlocksMin;
		opt->BlocksMin=opt->BlocksMax;
		opt->BlocksMax=tmp;
	}
	if (opt_e==0) {
		/* default BlockEnd */
		opt->BlockEnd=(opt->FileSize/opt->BlockSize)-1;
		if (opt->BlockEnd<0) {
			opt->BlockEnd=0;
		}
	}
	if (opt->BlockStart>opt->BlockEnd) {
		/* Block Start-End upside down. */
		off64_t		tmp;
		tmp=opt->BlockStart;
		opt->BlockStart=opt->BlockEnd;
		opt->BlockEnd=tmp;
	}
	if (opt->PathName==NULL) {
		printf("command line: Error: need working file path.\n");
		result=0;
	}
	if (*(opt->PathName)==0) {
		printf("command line: Error: need working file path.\n");
		result=0;
	}
	if (opt->BlockSize<(sizeof(off64_t)*2)) {
		printf("-b %" PRId64 ": Error: Should be more than %lu.\n",(int64_t)(opt->BlockSize), (unsigned long)(sizeof(off64_t)*2));
		result=0;
	}
	if ((opt->BlockSize%(sizeof(off64_t)))!=0) {
		printf("-b %" PRId64 ": Error: Should be a multiple %lu.\n",(int64_t)(opt->BlockSize), (unsigned long)(sizeof(off64_t)));
		result=0;
	}
	opt->FileSize=RoundUpBy(opt->FileSize,opt->BlockSize);
	return(result /* true */);
}

char	*do_only_options[]={"b","r","w"};
char	*do_read_file_options[]={"n","y","s"};

/*! Show command line arguments.
    @param p points TCommandLineOption structure to show.
    @return void nothing.
*/
void TCommandLineOptionShow(TCommandLineOption *opt)
{	printf
		("PathName: %s\n"
		 "FileSize(-f): %" PRId64 "\n"
		 "FillFile(-p): %c\n"
		 "DoReadFile(-r): %s\n"
		 "DoRandomAccess(-x): %s\n"
		 "DoDirect(-d): %c%c\n"
		 "DoMark(-m): %c\n"
		 "BlockSize(-b): %" PRId64 "\n"
		 "BlocksMin(-i): %" PRId64 "\n"
		 "BlocksMax(-a): %" PRId64 "\n"
		 "BlockStart(-o): %" PRId64 "\n"
		 "BlockEnd(-e): %" PRId64 "\n"
		 "Repeats(-n): %ld\n"
		 "Seed(-s): %ld\n"
		 ,opt->PathName
		 ,(int64_t)(opt->FileSize)
		 ,(opt->FillFile ? 'y' : 'n')
		 ,do_read_file_options[opt->DoReadFile]
		 ,do_only_options[opt->DoRandomAccess]
		 ,(opt->DoDirect ? 'y' : 'n')
		 ,(opt->DoDirectRandomRW ? 'Y' : 'N')
		 ,(opt->DoMark ? 'y' : 'n')
		 ,(int64_t)(opt->BlockSize)
		 ,(int64_t)(opt->BlocksMin)
		 ,(int64_t)(opt->BlocksMax)
		 ,(int64_t)(opt->BlockStart)
		 ,(int64_t)(opt->BlockEnd)
		 ,opt->Repeats
		 ,opt->Seed
		);
}

/*! Touch memory to make sure read data from device.
    @param b points buffer.
    @param len buffer length pointed by b.
    @return unsigned long summing up value.
*/
uint64_t TouchMemory(const char *b, long len)
{
	uint64_t	a;

	a=0;
	while (len>0) {
		/* Read some bytes in buffer. Stepping by ScPageSize.*/
		a+=*b;
		b+=ScPageSize;
		len-=ScPageSize;
	}
	return(a);
}

/*! Get file size using lseek64.
    @param fd file descriptor to get file size.
    @return off64_t file size.
*/
off64_t GetFileSizeFd(int fd)
{	off64_t	cur;
	off64_t	size;

	cur=lseek64(fd,0,SEEK_CUR);
	if (cur<0) {
		/* Can't get current file position. */
		return(cur);
	}
	size=lseek64(fd,0,SEEK_END);
	if (size>=0) {
		lseek64(fd,cur,SEEK_SET);
		/* ignore error. */
	}
	return(size);
}

/*! Make file image memory.
    @param b    points file image buffer to write.
    @param len  buffer length pointed by b.
*/
void MakeFileImage(char *b, long len)
{	while (len>0) {
		*b=lrand48()>>16;
		b++;
		len--;
	}
}

/*! Pre mark block address on file image memory.
    @param b0 points file image buffer to write.
    @param len0 buffer length pointed by b0.
    @param blocksize block size.
    
*/
void PreMarkFileImage(char *b0, long len0, long blocksize)
{
	char			*b;
	long			count;
	long			i;
	long			len;
	off64_t			a;

	len=len0;
	b=b0;
	while (len>0) {
		/* Zero block number and check sum area. */
		*(((off64_t *)b)+0)=0;
		*(((off64_t *)b)+1)=0;
		*((off64_t *)(b+blocksize-sizeof(a)))=0;
		b+=blocksize;
		len-=blocksize;
	}
	len=len0;
	b=b0;
	while (len>0) {
		count=blocksize;
		if (count>len) {
			/* Last block size is less than block size. */
			/* @note Is that really happen? */
			count=len;
		}
		a=0;
		i=0;
		while (i<count) {
			/* Summimg up image by u64. */
			a+=*((off64_t*)b);
			b+=sizeof(a);
			i+=sizeof(a);
		}
		/* Mark last u64 with complement. */
		*((off64_t*)(b-sizeof(a)))=-a;
		len-=blocksize;
	}
}

#define CHECK_STRICTRY_ERROR_DUMP_RANGE	(32)

/*! Strictly check file image on memory.
    @param b0 points file image buffer to check.
    @param len0 buffer length pointed by b0.
    @param block_number image block number pointed by b0.
    @param block_size block size.
    @param result check result holder.
    @return int !=LastBlockNumber: check sum error, *result==0. \
                ==LastBlockNumber: check sum ok, *result==1.
*/
off64_t CheckStrictlyFileImage(char *b, long len, off64_t block_number, long block_size, int *result)
{
	long			count;
	long			i;
	off64_t			a;
	off64_t			a0;

	while (len>0) {
		count=block_size;
		if (count>len) {
			/* Last block size is less than block size. */
			/* @note Is that really happen? */
			count=len;
		}
		a0= *(((off64_t*)b)+0)
		   +*(((off64_t*)b)+1);
		if (a0!=block_number) {
			/* Not much block number. */
			printf("%s: Error: Block number not match. expected(blocknumber)=%" PRId64 ", image=%" PRId64 "(0x%" PRIx64 ").\n"
				,__func__
				,(int64_t)block_number
				,(int64_t)a0
				,(int64_t)a0
			);
			DumpMemory(b,block_size,block_number*block_size);
			*result=0;
			return(block_number);
		}
		a=0;
		i=0;
		while (i<count) {
			/* Summimg up image by u64. */
			a+=*((off64_t*)b);
			b+=sizeof(a);
			i+=sizeof(a);
		}
		if (a!=0) {
			/* Not zero checksum. */
			printf("%s: Error: Checksum not match. blocknumber=%" PRId64 ", a=%" PRId64 "(0x%" PRIx64 ").\n"
				,__func__
				,(int64_t)block_number
				,(int64_t)a
				,(int64_t)a
			);
			DumpMemory(b-block_size,block_size,block_number*block_size);
			*result=0;
			return(block_number);
		}
		len-=block_size;
		block_number++;
	}
	*result=1;
	return(block_number);
}

/*! Light check file image on memory.
    @param b0 points file image buffer to check.
    @param len0 buffer length pointed by b0.
    @param block_number image block number pointed by b0.
    @param block_size block size.
    @param result check result holder.
    @return off64_t !=LastBlockNumber: check sum error, *result==0. \
                    ==LastBlockNumber: check sum ok, *result==1.
*/
off64_t CheckLightFileImage(char *b, long len, off64_t block_number, long block_size, int *result)
{	off64_t			a0;

	while (len>0) {
		a0= *(((off64_t*)b)+0)
		   +*(((off64_t*)b)+1);
		if (a0!=block_number) {
			/* Not much block number. */
			printf("%s: Error: Block number not match. expected(blocknumber)=%" PRId64 ", image=%" PRId64 "(0x%" PRIx64 ").\n"
				,__func__
				,(int64_t)block_number
				,(int64_t)a0
				,(int64_t)a0
			);
			DumpMemory(b,block_size,block_number*block_size);
			*result=0;
			return(block_number);
		}
		/* Step next block. */
		b+=block_size;
		len-=block_size;
		block_number++;
	}
	*result=1;
	return(block_number);
}


/*! Mark block address on file image.
    @param b points image buffer to write.
    @param len length to write.
    @param block_number block number to mark.
    @param block_size block size.
*/
void MarkFileImage(char *b, long len, off64_t block_number, off64_t block_size)
{	off64_t		a;

	while (len>0) {
		a=*(((off64_t*)b)+0)+*(((off64_t*)b)+1);
		*(((uint16_t*)b)+4+0)=(uint16_t)(lrand48()>>8);
		*(((uint16_t*)b)+4+1)=(uint16_t)(lrand48()>>8);
		*(((uint16_t*)b)+4+2)=(uint16_t)(lrand48()>>8);
		*(((uint16_t*)b)+4+3)=(uint16_t)(lrand48()>>8);
		*((off64_t*)(b))=block_number-*(((off64_t*)b)+1);
		*((off64_t*)(b-sizeof(a)+block_size))-=block_number-a;
		block_number++;
		b+=block_size;
		len-=block_size;
	}
}


/*! Fill(Write) working file up to FileSize.
    @param fd file descriptor.
    @param img point file image memory.
    @param imgsize buffer byte length pointed by img.
    @param opt Command Line option.
    @return int ==0 failed, !=0 success.
*/
int PreCreateFile(int fd, char *img, long imgsize, TCommandLineOption *opt)
{	off64_t		blockno;
	long		chunk;
	long		chunk_max;
	off64_t		start_pos;
	off64_t		print_pos;
	off64_t		cur_pos;
	off64_t		end_next_pos;
	long		i;

	struct timespec	ts_write_0;
	struct timespec	ts_print;
	struct timespec	ts_write_s;
	struct timespec	ts_write_e;
	struct timespec	ts_write_e_tmp;
	struct timespec	ts_write_ap;
	struct timespec	ts_write_aa;
	struct timespec	ts_mem_a;

	if (!img) {
		/* img is NULL. */
		printf("%s(): Error: Internal, buffer is not allocated.\n"
			, __func__
		);
		return(0 /* false */);
	}
	start_pos=opt->BlockSize*opt->BlockStart;
	/* Seek to start position. */
	cur_pos=lseek64(fd,start_pos,SEEK_SET);
	if (cur_pos<0) {
		/* seek error. */
		printf("%s: Error: lseek64(0) failed(1). %s(%d)\n",opt->PathName, strerror(errno),errno);
		return(0 /* false */);
	}

	chunk_max=opt->BlockSize*opt->BlocksMax;
	if (chunk_max>imgsize) {
		/* allocated buffer is small. */
		printf("%s(): Error: Internal, buffer is small. chunk_max=%ld, imgsize=%ld.\n"
			, __func__, chunk_max, imgsize
		);
		return(0 /* false */);
	}

	memset(&ts_write_ap,0,sizeof(ts_write_ap));
	memset(&ts_write_aa,0,sizeof(ts_write_aa));
	memset(&ts_mem_a,0,sizeof(ts_mem_a));

	i=0;
	blockno=opt->BlockStart;
	cur_pos=start_pos;
	print_pos=cur_pos;
	end_next_pos=opt->BlockSize*(opt->BlockEnd+1);

	printf("%s: Info: Fill working file. s=%" PRId64 ", e=%" PRId64 "\n",opt->PathName,
		start_pos, end_next_pos-(opt->BlockSize)
	);
	/*      0123456789  0123456789  0123456789  0123456789  cur_pos progress, Twrite, Twrite_total, Twrite_elapsed, Telapsed, Tmem_access_total */
	printf("   cur b/s,  total b/s, cur_el b/s,    elp b/s, cur_pos, progs, Twrite, Twrite_total, Twrite_elapsed, Telapsed, Tmem_access_total\n");

	if (clock_gettime(CLOCK_REALTIME,&ts_write_0)!=0) {
		printf("%s(): Error: clock_gettime failed. %s(%d)\n",__func__,strerror(errno),errno);
		return 0; /* failed */
	}
	ts_write_e=ts_write_0;
	ts_print=  ts_write_0;

	while (cur_pos<end_next_pos) {
		/* loop makes working file from BlockBegin to BlockEnd. */
		off64_t		tmp;
		ssize_t		wresult;
		int		done;

		chunk=chunk_max;
		tmp=end_next_pos-cur_pos;
		if (((off64_t)chunk)>tmp) {
			/* last chunk. */
			chunk=(long)(tmp);
		}
		if (opt->DoMark!=0) {
			MarkFileImage(img,chunk,blockno,opt->BlockSize);
		}
		done=0;
		clock_gettime(CLOCK_REALTIME,&ts_write_s);
		wresult=TryWrite(fd,img,chunk,&done);
		clock_gettime(CLOCK_REALTIME,&ts_write_e_tmp);
		if ((!done) || (wresult!=chunk)) {
			/* Can't write requested. */
			printf("%s: Error: Write failed. wresult=0x%lx,  chunk=0x%lx. %s(%d)\n"
				,opt->PathName, (long)wresult, chunk, strerror(errno), errno
			);
			return(0 /* false */);
		}

		timespecAdd(&ts_mem_a,&ts_mem_a,&ts_write_s);
		timespecSub(&ts_mem_a,&ts_mem_a,&ts_write_e);
		timespecAdd(&ts_write_aa,&ts_write_aa,&ts_write_e_tmp);
		timespecSub(&ts_write_aa,&ts_write_aa,&ts_write_s);
		ts_write_e=ts_write_e_tmp;

		blockno+=opt->BlocksMax;
		cur_pos+=chunk;
		{
			double		dt_write_elp;
			double		dt_write;
			double		dt_all;
			double		dt_mem;
			double		dt_elp;
			double		print_pos_delta;
			double		pos_delta;

			struct timespec	ts_delta;

			dt_write_elp=timespecToDouble(timespecSub(&ts_delta,&ts_write_e_tmp, &ts_print));
			if (  (dt_write_elp>=1.0)
			    ||(cur_pos>=end_next_pos)
			   ) {	/* Finish filling or elapsed 1 sec from last show. */
				dt_write=timespecToDouble(timespecSub(&ts_delta,&ts_write_aa, &ts_write_ap));
				dt_all=timespecToDouble(&ts_write_aa);
				dt_elp=timespecToDouble(timespecSub(&ts_delta,&ts_write_e_tmp, &ts_write_0));
				dt_mem=timespecToDouble(&ts_mem_a);
				print_pos_delta=cur_pos-print_pos;
				pos_delta=cur_pos-start_pos;
				printf("%10.4e, %10.4e, %10.4e, %10.4e, %" PRId64 ", %3.2f%%, %10.4e, %10.4e, %10.4e, %10.4e, %10.4e\n"
					, print_pos_delta/dt_write
					, pos_delta/dt_all
					, print_pos_delta/dt_write_elp
					, pos_delta/dt_elp
					, cur_pos
					, 100*pos_delta/((double)(end_next_pos-start_pos))
					, dt_write
					, dt_all
					, dt_write_elp
					, dt_elp
					, dt_mem
				);
				ts_print=ts_write_e_tmp;
				ts_write_ap=ts_write_aa;
				print_pos=cur_pos;
			}
		}

		i++;
	}
	/* Seek to start position. */
	cur_pos=lseek64(fd,start_pos,SEEK_SET);
	if (cur_pos<0) {
		/* seek error. */
		printf("%s: Error: lseek64(0) failed(2). %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}
	return(1 /* true */);
}

/*! Read working file up to FileSize.
    @param path 
    @param fd file descriptor.
    @param img point file image memory.
    @param imgsize buffer byte length pointed by img.
    @param opt Command Line option.
    @return int ==0 failed, !=0 success.
*/
int ReadFile(int fd, char *img, long imgsize, TCommandLineOption *opt)
{	off64_t		blockno;
	long		chunk;
	long		chunk_max;
	off64_t		start_pos;
	off64_t		print_pos;
	off64_t		cur_pos;
	off64_t		end_next_pos;
	long		i;

	struct timespec	ts_read_0;
	struct timespec	ts_print;
	struct timespec	ts_read_s;
	struct timespec	ts_read_e;
	struct timespec	ts_read_e_tmp;
	struct timespec	ts_read_ap;
	struct timespec	ts_read_aa;
	struct timespec	ts_mem_a;

	if (!img) {
		/* img is NULL. */
		printf("%s(): Error: Internal, buffer is not allocated.\n"
			, __func__
		);
		return(0 /* false */);
	}
	start_pos=opt->BlockSize*opt->BlockStart;
	/* Seek to start position. */
	cur_pos=lseek64(fd,start_pos,SEEK_SET);
	if (cur_pos<0) {
		/* seek error. */
		printf("%s: Error: lseek64(0) failed(1). %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}

	chunk_max=opt->BlockSize*opt->BlocksMax;
	if (chunk_max>imgsize) {
		/* allocated buffer is small. */
		printf("%s(): Error: Internal, buffer is small. chunk_max=%ld, imgsize=%ld.\n"
			, __func__, chunk_max, imgsize
		);
		return(0 /* false */);
	}

	memset(&ts_read_ap,0,sizeof(ts_read_ap));
	memset(&ts_read_aa,0,sizeof(ts_read_aa));
	memset(&ts_mem_a,0,sizeof(ts_mem_a));

	i=0;
	blockno=opt->BlockStart;
	cur_pos=start_pos;
	print_pos=cur_pos;
	end_next_pos=opt->BlockSize*(opt->BlockEnd+1);

	printf("%s: Info: Read working file. s=%" PRId64 ", e=%" PRId64 "\n",opt->PathName,
		start_pos, end_next_pos-(opt->BlockSize)
	);
	/*      0123456789  0123456789  0123456789  0123456789 cur_pos progress, Tread, Tread_total, Tread_elapsed, Telapsed, Tmem_access_total, */
	printf("   cur b/s,  total b/s, cur_el b/s,    elp b/s, cur_pos, progs, Tread, Tread_total, Tread_elapsed, Telapsed, Tmem_access_total, \n");

	clock_gettime(CLOCK_REALTIME,&ts_read_0);
	ts_read_e=ts_read_0;
	ts_print= ts_read_0;
	while (cur_pos<end_next_pos) {
		/* loop makes working file from BlockBegin to BlockEnd. */
		off64_t		tmp;
		ssize_t		rresult;
		int		done;

		chunk=chunk_max;
		tmp=end_next_pos-cur_pos;
		if (((off64_t)chunk)>tmp) {
			/* last chunk. */
			chunk=(long)(tmp);
		}

		done=0;
		clock_gettime(CLOCK_REALTIME,&ts_read_s);
		rresult=TryRead(fd,img,chunk,&done);
		clock_gettime(CLOCK_REALTIME,&ts_read_e_tmp);
		if ((!done) || (rresult!=chunk)) {
			/* Can't write requested. */
			printf("%s: Error: Read failed. rresult=0x%lx,  chunk=0x%lx. %s\n"
				,opt->PathName, (long)rresult, chunk, strerror(errno)
			);
			return(0 /* false */);
		}
		timespecAdd(&ts_mem_a,&ts_mem_a,&ts_read_s);
		timespecSub(&ts_mem_a,&ts_mem_a,&ts_read_e);
		timespecAdd(&ts_read_aa,&ts_read_aa,&ts_read_e_tmp);
		timespecSub(&ts_read_aa,&ts_read_aa,&ts_read_s);
		ts_read_e=ts_read_e_tmp;

		if (opt->DoMark!=0) {
			/* Marked block. */
			int		r;
			off64_t		block_check;
			r=0;
			switch (opt->DoReadFile) {
				case DO_READ_FILE_LIGHT:
					block_check=CheckLightFileImage(img, chunk, blockno, opt->BlockSize, &r);
					break;
				case DO_READ_FILE_STRICT:
					block_check=CheckStrictlyFileImage(img, chunk, blockno, opt->BlockSize, &r);
					break;
				default:
					printf("%s: Error: Internal, unexpected DoReadFile. DoRead=%d\n"
						,__func__
						,opt->DoReadFile
					);
					return 0;
			}
			if (r==0) {
				printf("%s: Error: Check sum error. block=%" PRId64 ".\n"
					,opt->PathName
					,(int64_t)block_check
				);
				return 0;
			}
		} else {
			TouchSums+=TouchMemory(img,chunk);
		}

		blockno+=opt->BlocksMax;
		cur_pos+=chunk;
		{
			double		dt_read_elp;
			double		dt_read;
			double		dt_all;
			double		dt_mem;
			double		dt_elp;

			double		print_pos_delta;
			double		pos_delta;

			struct timespec	ts_delta;

			dt_read_elp=timespecToDouble(timespecSub(&ts_delta,&ts_read_e_tmp, &ts_print));
			if (  (dt_read_elp>=1.0)
			    ||(cur_pos>=end_next_pos)
			   ) {	/* Finish filling or elapsed 1 sec from last show. */
				dt_read=timespecToDouble(timespecSub(&ts_delta,&ts_read_aa,    &ts_read_ap));
				dt_all= timespecToDouble(&ts_read_aa);
				dt_elp= timespecToDouble(timespecSub(&ts_delta,&ts_read_e_tmp, &ts_read_0));
				dt_mem= timespecToDouble(&ts_mem_a);
				print_pos_delta=cur_pos-print_pos;
				pos_delta=cur_pos-start_pos;
				printf("%10.4e, %10.4e, %10.4e, %10.4e, %" PRId64 ", %3.2f%%, %10.4e, %10.4e, %10.4e, %10.4e, %10.4e\n"
					, print_pos_delta/dt_read
					, pos_delta/dt_all
					, print_pos_delta/dt_read_elp
					, pos_delta/dt_elp
					, cur_pos
					, 100*pos_delta/((double)(end_next_pos-start_pos))
					, dt_read
					, dt_all
					, dt_read_elp
					, dt_elp
					, dt_mem
				);
				ts_print=ts_read_e_tmp;
				ts_read_ap=ts_read_aa;
				print_pos=cur_pos;
			}
		}
		i++;
	}
	/* Seek to start position. */
	cur_pos=lseek64(fd,start_pos,SEEK_SET);
	if (cur_pos<0) {
		/* seek error. */
		printf("%s: Error: lseek64(0) failed(2). %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}
	return(1 /* true */);
}

/*! Random read/write working file.
    @param fd file descriptor.
    @param img point file image memory.
    @param imgsize buffer byte length pointed by img.
    @param opt Command Line option.
    @return int ==0 failed, !=0 success.

*/
int RandomRWFile(int fd, char *img, long imgsize, char *mem, long memsize, TCommandLineOption *opt)
{	off64_t		seek_size;
	off64_t		end_next_pos;
	off64_t		area_blocks;
	off64_t		seekto_prev;
	long		repeats;
	long		i;
	int		result;

	struct timespec	ts_0;
	struct timespec	ts_mem_delta;
	struct timespec	ts_rw_delta;
	struct timespec	ts_op_done;

	result=1;
	seek_size=GetFileSizeFd(fd);
	end_next_pos=opt->BlockSize*(opt->BlockEnd+1);
	area_blocks=opt->BlockEnd-opt->BlockStart+1;
	seekto_prev=-1;
	/* Record time at tests begin. */
	if (clock_gettime(CLOCK_REALTIME,&ts_0)!=0) {
		printf("%s(): Error: clock_gettime failed. %s\n",__func__,strerror(errno));
		return 0; /* failed */
	}
	printf("i, elp, rw, pos, len, rtime, bps, touchtime\n");
	repeats=opt->Repeats;
	i=0;
	while ((i<repeats) && (result!=0)) {
		off64_t		seekto_block;
		off64_t		seekto;
		off64_t		seekto_delta;
		off64_t		seekresult;
		size_t		length;
		int		ioresult;

		struct timespec	ts_mem;
		struct timespec	ts_rw_start;
		struct timespec	ts_rw_done;

		char		read_write;
		unsigned char	rw_act;

		/* Calc random seek position and size. */
		seekto_block=(off64_t)(drand48()*(double)area_blocks)+opt->BlockStart;
		seekto=(opt->BlockSize)*seekto_block;
		length=(opt->BlockSize)*((long)(drand48()*(double)(opt->BlocksMax-opt->BlocksMin+1))+opt->BlocksMin);
		if ((length+seekto)>end_next_pos) {
			/* over runs at block end. */
			length=end_next_pos-seekto;
		}
		if ((length+seekto)>seek_size) {
			/* over runs at end of file. */
			length=seek_size-seekto;
		}
		/* Seek random. */
		seekresult=lseek64(fd,seekto,SEEK_SET);
		if (seekresult<0) {
			printf("%s: Error: seek failed. seekto=0x%.16" PRIx64 ", seekresult=0x%.16" PRIx64 ". %s\n"
				,opt->PathName,(int64_t)seekto,(int64_t)seekresult,strerror(errno)
			);
			return 0; /* failed */
		}
		rw_act=((lrand48()>>16UL)&0x01UL);
		switch (opt->DoRandomAccess) {
			case DO_RANDOM_ACCESS_BOTH: {
				/* Both read and write. */
				break;
			}
			case DO_RANDOM_ACCESS_READ: {
				/* Do Only Read. */
				/* Force read. */
				rw_act=0;
				break;
			}
			case DO_RANDOM_ACCESS_WRITE: {
				/* Do Only Write. */
				/* Force write. */
				rw_act=1;
				break;
			}
		}
		if (rw_act==0) {
			/* Read blocks. */
			int	sum_result;
			off64_t	block_check;
			int	done;
			
			done=0;
			/* Record time at read. */
			clock_gettime(CLOCK_REALTIME,&ts_rw_start);
			ioresult=TryRead(fd,mem,length,&done);
			/* Record time at done read. */
			clock_gettime(CLOCK_REALTIME,&ts_rw_done);
			if ((!done) || (ioresult!=length)) {
				printf("%s: Error: read failed. %s length=0x%lx, ioresult=0x%lx.\n"
				,opt->PathName,strerror(errno),(long)length,(long)(ioresult));
				return 0; /* failed */
			}
			if (opt->DoMark!=0) {
				sum_result=0;
				block_check=CheckStrictlyFileImage(
					mem,length
					,seekto_block,opt->BlockSize
					,&sum_result
				);
				if (sum_result==0) {
					/* Check sum error. */
					printf
						("%s: Error: Check sum error. block=%" PRId64 ".\n"
						,opt->PathName
						,(int64_t)block_check
						);
					result=0;
					/* do remainig process. */
				}
			}  else {/* Only do touch. */
				TouchSums+=TouchMemory(mem,length);
			}
			clock_gettime(CLOCK_REALTIME,&ts_mem);
			timespecSub(&ts_rw_delta,&ts_rw_done,&ts_rw_start);
			timespecSub(&ts_mem_delta,&ts_mem,&ts_rw_done);
			memcpy(&ts_op_done,&ts_mem,sizeof(ts_op_done));
			read_write='r';
		} else {/* write blocks. */
			char	*imgwork;
			int	done;

			clock_gettime(CLOCK_REALTIME,&ts_mem);
			/* Choose image to write by random. */
			imgwork=img+((opt->BlockSize)*(off64_t)(drand48()*((double)(opt->BlocksMax))));
			if (opt->DoMark) {
				MarkFileImage(imgwork,length,seekto_block,opt->BlockSize);
			}
			done=0;
			clock_gettime(CLOCK_REALTIME,&ts_rw_start);
			ioresult=TryWrite(fd,imgwork,length,&done);
			/* Record time at touch. */
			clock_gettime(CLOCK_REALTIME,&ts_rw_done);
			if ((!done) || (ioresult!=length)) {
				printf("%s: Error: write failed. %s length=0x%lx, ioresult=0x%lx.\n"
				,opt->PathName,strerror(errno),(long)length,(long)ioresult);
				return 0;
			}
			timespecSub(&ts_rw_delta,&ts_rw_done,&ts_rw_start);
			timespecSub(&ts_mem_delta,&ts_rw_start,&ts_mem);
			memcpy(&ts_op_done,&ts_rw_done,sizeof(ts_op_done));
			read_write='w';
		}
		if (seekto_prev>=0) {
			seekto_delta=seekto-seekto_prev;
		} else {
			seekto_delta=0;
		}

		{	double		rw_time;
			double		mem_time;
			struct timespec	ts_elapsed;

			rw_time=timespecToDouble(&ts_rw_delta);
			mem_time=timespecToDouble(&ts_mem_delta);
			/*       i, elp, rw, pos, len, rw_time, bps, touchtime */
			printf("%8ld, %10.4e, %c, 0x%.16" PRIx64 ", 0x%.8lx, %10.4e, %10.4e, %10.4e\n"
				,i
				,timespecToDouble(timespecSub(&ts_elapsed,&ts_op_done,&ts_0))
				,read_write
				,seekto
				,(long)length
				,rw_time
				,((double)length)/rw_time
				,mem_time
			);
		}
		seekto_prev=seekto;
		i++;
	}
	return result;
}

#define	LARGE_FILE_SIZE	(1024L*1024L*2)

int MainTest(TCommandLineOption *opt)
{	int		result;
	int		fd;
	int		flags;
	int		fd_flags_base;
	int		fd_flags_add;

	char		*mem;
	long		memsize;

	char		*img;
	long		imgsize;

	struct stat64	st64;
	off64_t		seek_size;

	result=1 /* true */;
	/* Initialize random seed. */
	srand48(opt->Seed);

	/* O_NOATIME issue error EPERM. */
	fd_flags_base=O_RDWR|O_CREAT /* | O_NOATIME */;

	if (opt->FileSize>=LARGE_FILE_SIZE) {
		fd_flags_base|=O_LARGEFILE;
	}

	fd_flags_add=0;
	if (opt->DoDirect!=0) {
		fd_flags_add|=O_DIRECT;
	}
	flags=fd_flags_base | fd_flags_add;
	fd=open(opt->PathName
		,flags
		,S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH
	);
	if (fd<0) {
		/* Can't open. */
		printf("%s: Error: open failed. %s\n",opt->PathName,strerror(errno));
		return(0 /* false */);
	}
	printf("%s: Info: open. fd=%d, flags=0x%x\n",opt->PathName, fd, flags);
	if (fstat64(fd,&st64)!=0) {
		/* Can't stat. */
		printf("%s: Error: fstat failed. %s\n",opt->PathName,strerror(errno));
		result=0 /* false */;
		goto EXIT_CLOSE;
	}
	/* allocate read buffer mem. */
	memsize=RoundUpBy((opt->BlockSize*opt->BlocksMax),ScPageSize);
	mem=mmap(NULL,memsize
		,PROT_READ|PROT_WRITE,MAP_ANONYMOUS|MAP_PRIVATE
		,-1,0);

	if (mem==MAP_FAILED) {
		printf("%s(): Error: mmap failed(mem). %s\n",__func__,strerror(errno));
		result=0 /* false */;
		goto EXIT_CLOSE;
	}

	/* allocate write buffer img. */
	imgsize=RoundUpBy((opt->BlockSize*opt->BlocksMax)*2,ScPageSize);
	img=mmap(NULL,imgsize
		,PROT_READ|PROT_WRITE,MAP_ANONYMOUS|MAP_PRIVATE
		,-1,0);

	if (img==MAP_FAILED) {
		printf("%s(): Error: mmap failed(img). %s\n",__func__,strerror(errno));
		result=0 /* false */;
		goto EXIT_UNMAP_MEM;
	}
	MakeFileImage(img,imgsize);
	if (opt->DoMark!=0) {
		PreMarkFileImage(img,imgsize,opt->BlockSize);
	}
	seek_size=GetFileSizeFd(fd);
	if (seek_size<0) {
		printf("%s(): Error: lseek64 to get file size failed. %s\n",__func__,strerror(errno));
		result=0 /* false */;
		goto EXIT_UNMAP_IMG;
	}
	if (opt->BlockStart<0) {
		/* Command line option -o Start block missing. */
		/* Default start position. */
		opt->BlockStart=0;
	}
	if (seek_size==0) {
		/* Created new file or opened zero size file. */
		off64_t	blocks_file;

		seek_size=opt->FileSize;
		if (seek_size<=0) {
			printf("%s: Error: Use option -f to set file size.\n",opt->PathName);
			result=0 /* false */;
			goto EXIT_UNMAP_IMG;
		}
		blocks_file=opt->FileSize/opt->BlockSize;
		if (opt->BlockEnd>=blocks_file) {
			/* command line option specifies more blocks than FileSize. */
			opt->BlockEnd=blocks_file-1;
			if (opt->BlockEnd<0) {
				/* note: It may happen "FileSize is zero" and "BlockEnd is zero". */
				opt->BlockEnd=0;
			}
		}
		TCommandLineOptionShow(opt);
		if (opt->FillFile) {
			/* Fill file. */
			if (!PreCreateFile(fd,img,imgsize,opt)) {
				/* Fail to create. */
				result=0 /* false */;
				goto EXIT_UNMAP_IMG;
			}
		} else {/* Truncate file. */
			if (ftruncate64(fd,opt->FileSize)!=0) {
				printf("%s: Error: ftruncate64 failed. %s\n",opt->PathName,strerror(errno));
				result=0 /* false */;
				goto EXIT_UNMAP_IMG;
			}
		}
	} else {/* open exist file. */
		off64_t	blocks_file;
		if (seek_size!=opt->FileSize) {
			/* File size not match. */
			if (opt->FileSize!=0) {
				if (!(S_ISBLK(st64.st_mode))) {
					/* Not block device. */
					if (ftruncate64(fd,opt->FileSize)!=0) {
						/* fail to truncate. */
						printf("%s: Error: ftruncate64 failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
						result=0 /* false */;
						goto EXIT_UNMAP_IMG;
					}
				} else {
					/* Maybe block device. */
					opt->FileSize=seek_size;
				}
			} else {/* Use exist file as is. */
				opt->FileSize=seek_size;
			}
		}
		blocks_file=opt->FileSize/opt->BlockSize;
		if (opt->BlockEnd>=blocks_file) {
			opt->BlockEnd=blocks_file-1;
			if (opt->BlockEnd<0) {
				opt->BlockEnd=0;
			}
		}
		TCommandLineOptionShow(opt);
		if (opt->FillFile) {
			/* Fill file. */
			if (!PreCreateFile(fd,img,imgsize,opt)) {
				/* Fail to create. */
				result=0 /* false */;
				goto EXIT_UNMAP_IMG;
			}
		}
	}

	if (close(fd)!=0) {
		printf("%s: Error: close failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
		fd=INVALID_FD;
		result=0;
		goto EXIT_UNMAP_IMG;
	}
	printf("%s: Info: close. fd=%d\n",opt->PathName, fd);

	fd_flags_add=0;
	if (opt->DoDirectRandomRW!=0) {
		fd_flags_add|=O_DIRECT;
	}

	flags=fd_flags_base | fd_flags_add;
	fd=open(opt->PathName
		,flags
		,S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH
	);
	if (fd<0) {
		/* Can't open. */
		printf("%s: Error: open failed. %s\n",opt->PathName,strerror(errno));
		goto EXIT_UNMAP_IMG;
	}
	printf("%s: Info: open. fd=%d, flags=0x%x\n",opt->PathName, fd, flags);

	if (!RandomRWFile(fd,img,imgsize,mem,memsize,opt)) {
		/* Random read/write failed. */
		printf("%s: Error: random read/write failed. %s\n",opt->PathName,strerror(errno));
		result=0;
	}

	if (close(fd)!=0) {
		printf("%s: Error: close failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
		result=0;
		goto EXIT_UNMAP_IMG;
	}
	printf("%s: Info: close. fd=%d\n",opt->PathName, fd);

	fd_flags_add=0;
	if (opt->DoDirect!=0) {
		fd_flags_add|=O_DIRECT;
	}

	flags=fd_flags_base | fd_flags_add;
	fd=open(opt->PathName
		,flags
		,S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH
	);

	if (fd<0) {
		/* Can't open. */
		printf("%s: Error: open failed. %s\n",opt->PathName,strerror(errno));
		goto EXIT_UNMAP_IMG;
	}
	printf("%s: Info: open. fd=%d, flags=0x%x\n",opt->PathName, fd, flags);

	if (opt->DoReadFile!=DO_READ_FILE_NO) {
		/* Do sequential read. */
		if (!ReadFile(fd,img,imgsize,opt)) {
			printf("%s: Error: Sequential read failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
			result=0;
		}
	}

EXIT_UNMAP_IMG:;
	if (munmap(img,imgsize)!=0) {
		printf("%s(): Error: munmap failed(img). %s\n",__func__,strerror(errno));
		return(0);
	}
EXIT_UNMAP_MEM:;
	if (munmap(mem,memsize)!=0) {
		printf("%s(): Error: munmap failed(mem). %s\n",__func__,strerror(errno));
		return(0);
	}
EXIT_CLOSE:;
	if (fd!=INVALID_FD) {
		if (close(fd)!=0) {
			printf("%s: Error: close failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
			result=0;
		}
		printf("%s: Info: close. fd=%d\n",opt->PathName, fd);
	}
	if (opt->DoMark==0) {
		/* Skip check, only touch memory. */
		printf("TouchSums: Info: 0x%" PRIx64 "\n",TouchSums);
	}
	return(result /* true. */);
}

void show_help(void)
{	printf(
	"Command line: [-f n] [-p{y|n}] [-x{b|r|w}] [-d{y|n}] [-m{y|n}] [-b n] [-i n] [-a n] [-n n] [-s n] path_name\n"
	"-f n work file size.\n"
	"-p{y|n} Pre fill file with initial image(y: fill, n: truncate)(%c).\n"
	"-r{y|n} Read file start block to end block (s: read strict check, y: read light check, n: do nothing)(%s).\n"
	"-x{b|r|w} Random r/w method (b: Do both read and write, r: Do read only, w: Do write only)(%s).\n"
	"-d{y|n|Y|N}.. Add O_DIRECT flag at sequential r/w (y: add, n: not add), at random r/w(Y: add, N: not add)(%c%c).\n"
	"-m{y|n} Do block number Marking and check.(%c).\n"
	"-b n block size(%d).\n"
	"-i n Minimum blocks to read/write(%d).\n"
	"-a n Maximum blocks to read/write(%d).\n"
	"-o n Start block number to read/write(%d).\n"
	"-e n End block number to read/write(%d).\n"
	"-n n number of repeats(%d).\n"
	"-s n random seed number(%d). \n"
	"path_name: Device or file path name to test.\n"
	,(DEF_FillFile ? 'y' : 'n')
	,do_read_file_options[DEF_DoReadFile]
	,do_only_options[DEF_DoRandomAccess]
	,(DEF_DoDirect ? 'y' : 'n')
	,(DEF_DoDirectRandomRW ? 'Y' : 'N')
	,(DEF_DoMark ? 'y' : 'n')
	,DEF_BlockSize
	,DEF_BlocksMin,DEF_BlocksMax
	,0,0
	,DEF_Repeats, DEF_Seed
	);
	printf(
	"Output formats:\n"
	"count, elapsed_time, rw, wait_time, seek_delta, seek_delta_ratio, seek_pos, read_length, "
	"read_time, read_speed, touch_time\n"
	);
}

int main(int argc, char **argv)
{
	/* Get Page Size. */
	ScPageSize=sysconf(_SC_PAGESIZE);
	if (!TCommandLineOptionParseArgs(&CommandLine,argc,argv)) {
		show_help();
		return(1);
	}
	if (!MainTest(&CommandLine)) {
		printf("%s: Fail: Test FAIL.\n",CommandLine.PathName);
		return(2);
	}
	printf("%s: Pass: Test PASS.\n",CommandLine.PathName);
	return(0);
}

