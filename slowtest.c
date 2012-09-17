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

/*! Memory page size. 
    Set the sysconf(_SC_PAGESIZE) value in main().
*/
long	ScPageSize=4096;

#define	DO_ONLY_NO	(0) /* should be 0 */
#define	DO_ONLY_READ	(1)
#define	DO_ONLY_WRITE	(2)

#define	DO_OPTION_NO	(0) /* should be 0 */
#define	DO_OPTION_YES	(1)

#define	DEF_FillFile	(0)
#define	DEF_FileSize	(0)
#define	DEF_BlockSize	(4096)
#define	DEF_BlocksMin	(256)
#define	DEF_BlocksMax	(1024)
#define	DEF_BlockStart	(0)
#define	DEF_BlockEnd	(INT64_MAX)
#define	DEF_Repeats	(1000)
#define	DEF_Seed	(0)
#define	DEF_DoOnly	(DO_ONLY_NO)
#define	DEF_DoDirect	(DO_OPTION_YES)
#define	DEF_DoMark	(DO_OPTION_YES)

/*! define: Measure delayed read behavior.
    undef: Don't measure delayed read behavior.
*/
/* #define	MEASURE_DELAYED_READ */

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
	int			FillFile;	/*!< Fill work file. */
	int			DoOnly;		/*!< Do Both, Do Read only, Do Write only. */
	int			DoDirect;	/*!< Do O_DIRECT. io */
	int			DoMark;		/*!< Do Block Marking. */
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
	.DoOnly=DEF_DoOnly,
	.DoDirect=DEF_DoDirect,
	.DoMark=DEF_DoMark
};

#if (defined(MEASURE_DELAYED_READ))
/*! Accumulate numbers from touched memory. */
uint64_t	TouchSums=0;
#endif /* (defined(MEASURE_DELAYED_READ)) */

/*! Store milli second to timespec.
    @arg ts point timespec to store.
    @arg msec time in milli second.
*/
void timespecLoadMilliSec(struct timespec *ts, long msec)
{	ldiv_t		sec_milli;

	sec_milli=ldiv(msec,1000);
	sec_milli.rem*=1000L*1000L;	/* milli to micro to nano. */
	ts->tv_sec= sec_milli.quot;
	ts->tv_nsec=sec_milli.rem;
}

/*! Convert timespec to double.
    @arg ts points timespec structure.
    @return double second.
*/
double timespecToDouble(const struct timespec *ts)
{	return((double)(ts->tv_sec)+(ts->tv_nsec)/(1000.0*1000.0*1000.0));
}

/*! Sub timespecs. *y=*a-*b.
    @arg y point timespec structure to store *a-*b
    @arg a point timespec structure.
    @arg b point timespec structure.
    @return struct timespec pointer equal to y.
    @note *a means end time, *b means start time.
*/
struct timespec *timespecSub(struct timespec *y, const struct timespec *a, const struct timespec *b)
{	struct	timespec tsa;
	struct	timespec tsb;

	tsa=*a;
	tsb=*b;
	y->tv_sec= tsa.tv_sec- tsb.tv_sec;
	y->tv_nsec=tsa.tv_nsec-tsb.tv_nsec;
	if ((y->tv_nsec)<0) {
		/* borrow */
		y->tv_sec--;
		y->tv_nsec+=1000L*1000L*1000L;
	}
	return(y);
}

/*! Add timespecs. *y=*a+*b.
    @arg y point timespec structure to store *a+*b
    @arg a point timespec structure.
    @arg b point timespec structure.
    @return struct timespec pointer equal to y.
*/
struct timespec *timespecAdd(struct timespec *y, const struct timespec *a, const struct timespec *b)
{	struct	timespec tsa;
	struct	timespec tsb;

	tsa=*a;
	tsb=*b;
	y->tv_sec= tsa.tv_sec+ tsb.tv_sec;
	y->tv_nsec=tsa.tv_nsec+tsb.tv_nsec;
	if ((y->tv_nsec)>=1000L*1000L*1000L) {
		/* Carry. */
		y->tv_sec++;
		y->tv_nsec-=1000L*1000L*1000L;
	}
	return(y);
}

/*! Round up.
    @arg a  value to round up.
    @arg by round step value.
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
    @arg p  point char array to parse unsigned long number.
    @arg p2 point char* to store pointer at stopping parse.
    @arg radix default radix to parse.
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
    @arg buf point char buffer to store hex string.
    @arg a long long value to convert signed hex.
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

#define TRY_WRITE_MAX	(1000)

/*! Try write.
    Continue write, until all requested bytes are written.
    @arg fd  file descriptor to write bytes.
    @arg b   points byte array to write.
    @arg len bytes to write.
    @arg done points int variable to store success(!=0) or failed(==0).
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
    @arg fd  file descriptor to read bytes.
    @arg b   points byte array to store reads.
    @arg len bytes to read.
    @arg done points int variable to store success(!=0) or failed(==0).
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
    @arg buf    point memory to HEX dump.
    @arg n      number of bytes to dump.
    @arg offset meaning offset address pointed by buf.
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
    @arg opt points TCommandLineOption structure to store parsed values.
    @arg argc  the argc value same as main() function's argc.
    @arg argv0 the argv value same as main() function's argv.
    @return int 1: Success, 0: Failed (found invalid argument).
*/
int TCommandLineOptionParseArgs(TCommandLineOption *opt, char argc, char **argv0)
{	char	*p;
	char	*p2;
	char	*optval;
	char	**argv;
	char	opt_e;

	argv=argv0;
	argc--;
	argv++;
	opt_e=0;
	while ((argc>0) && ((p=*argv)!=NULL)) {
		if (*p=='-') {
			/* option. */
			int	optval_next;
			char	opt_kind;

			optval_next=0;
			optval="";
			p++;
			opt_kind=*p;
			if (opt_kind) {
				/* It may be option. */
				p++;
				if (*p) {
					/* The option and it's value are concatenated. */
					optval=p;
				} else {
					/* The option and it's value are separated. */
					if ((argc>=2) && (*(argv+1))) {
						/* The next argv is available. */
						optval_next=1;
						optval=*(argv+1);
					}
				}
			}
			switch (opt_kind) {
				case 'b': {
					/* -b block size. */
					if (*optval) {
						off64_t	save;
						save=opt->BlockSize;
						opt->BlockSize=strtoulkmg(optval,&p2,0);
						if (opt->BlockSize<=0) {
							/* Zero or negative BlockSize. */
							opt->BlockSize=save;
						}
					}
					break;
				}
				case 'f': {
					/* -f file size. */
					if (*optval) {
						opt->FileSize=strtoulkmg(optval,&p2,0);
					}
					break;
				}
				case 'p': {
					/* -p pre fill. */
					switch (*optval) {
						case 'y': {
							/* Do fill file. */
							opt->FillFile=1;
							break;
						}
						case 'n': {
							/* Do truncate file. */
							opt->FillFile=0;
							break;
						}
						default: {
							/* invalid. */
							printf("%s: Need parameter value y|n.\n",*argv);
							break;
						}
					}
					break;
				}
				case 'x': {
					/* -x do only. */
					switch (*optval) {
						case 'b': {
							/* Both read and write. */
							break;
							opt->DoOnly=DO_ONLY_NO;
							break;
						}
						case 'r': {
							/* Read only. */
							opt->DoOnly=DO_ONLY_READ;
							break;
						}
						case 'w': {
							/* Write only. */
							opt->DoOnly=DO_ONLY_WRITE;
							break;
						}
						default: {
							/* invalid. */
							printf("%s: Need parameter value b|r|w.\n",*argv);
							break;
						}
					}
					break;
				}
				case 'd': {
					/* -d with O_DIRECT. */
					switch (*optval) {
						case 'y': {
							/* open with O_DIRECT. */
							opt->DoDirect=DO_OPTION_YES;
							break;
						}
						case 'n': {
							/* open without O_DIRECT. */
							opt->DoDirect=DO_OPTION_NO;
							break;
						}
						default: {
							/* invalid. */
							printf("%s: Need parameter value y|n.\n",*argv);
							break;
						}
					}
					break;
				}
				case 'm': {
					/* -m Do Block Number Marking. */
					switch (*optval) {
						case 'y': {
							/* open with O_DIRECT. */
							opt->DoMark=DO_OPTION_YES;
							break;
						}
						case 'n': {
							/* open without O_DIRECT. */
							opt->DoMark=DO_OPTION_NO;
							break;
						}
						default: {
							/* invalid. */
							printf("%s: Need parameter value y|n.\n",*argv);
							break;
						}
					}
					break;
				}
				case 'i': {
					/* -i blocks min. */
					if (*optval) {
						opt->BlocksMin=strtoulkmg(optval,&p2,0);
					}
					break;
				}
				case 'a': {
					/* -a blocks max. */
					if (*optval) {
						opt->BlocksMax=strtoulkmg(optval,&p2,0);
					}
					break;
				}
				case 'o': {
					/* -o origin block. (start block). */
					if (*optval) {
						opt->BlockStart=strtoulkmg(optval,&p2,0);
					}
					break;
				}
				case 'e': {
					/* -e end block. */
					if (*optval) {
						opt->BlockEnd=strtoulkmg(optval,&p2,0);
						opt_e=1;
					}
					break;
				}
				case 'n': {
					/* -n repeat counts. */
					if (*optval) {
						opt->Repeats=strtol(optval,&p2,0);
					}
					break;
				}
				case 's': {
					/* -s random seed number. */
					if (*optval) {
						opt->Seed=strtol(optval,&p2,0);
					}
					break;
				}
				case 'h': {
					/* -h show help. */
					return(0);
				}
				default: {
					printf("%s: Invalid option -%c\n",*argv0,opt_kind);
					return(0 /* false */);
				}
			}
			argc-=optval_next;
			argv+=optval_next;
		} else {
			/* Path name. */
			opt->PathName=p;
		}
		argc--;
		argv++;
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
		printf("command line: need working file path.\n");
		return(0);
	}
	if (*(opt->PathName)==0) {
		printf("command line: need working file path.\n");
		return(0);
	}
	if (opt->BlockSize<(sizeof(off64_t)*2)) {
		printf("-b %" PRId64 ": Should be more than %lu.\n",(int64_t)(opt->BlockSize), (unsigned long)(sizeof(off64_t)*2));
		return(0);
	}
	if ((opt->BlockSize%(sizeof(off64_t)))!=0) {
		printf("-b %" PRId64 ": Should be a multiple %lu.\n",(int64_t)(opt->BlockSize), (unsigned long)(sizeof(off64_t)));
		return(0);
	}
	opt->FileSize=RoundUpBy(opt->FileSize,opt->BlockSize);
	return(1 /* true */);
}

char	*do_only_options[]={"b","r","w"};

/*! Show command line arguments.
    @arg p points TCommandLineOption structure to show.
    @return void nothing.
*/
void TCommandLineOptionShow(TCommandLineOption *opt)
{	printf
		("PathName: %s\n"
		 "FileSize(-f): %" PRId64 "\n"
		 "FillFile(-p): %c\n"
		 "DoOnly(-x): %s\n"
		 "DoDirect(-d): %c\n"
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
		 ,do_only_options[opt->DoOnly]
		 ,(opt->DoDirect ? 'y' : 'n')
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

#if (defined(MEASURE_DELAYED_READ))
/*! Touch memory to make sure read data from device.
    @arg b points buffer.
    @arg len buffer length pointed by b.
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
#endif /* (defined(MEASURE_DELAYED_READ)) */

/*! Get file size using lseek64.
    @arg fd file descriptor to get file size.
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
    @arg b    points file image buffer to write.
    @arg len  buffer length pointed by b.
*/
void MakeFileImage(char *b, long len)
{	while (len>0) {
		*b=lrand48()>>16;
		b++;
		len--;
	}
}

/*! Pre mark block address on file image memory.
    @arg b0 points file image buffer to write.
    @arg len0 buffer length pointed by b0.
    @arg blocksize block size.
    
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

/*! Strictry check file image on memory.
    @arg b0 points file image buffer to check.
    @arg len0 buffer length pointed by b0.
    @arg block_number image block number pointed by b0.
    @arg block_size block size.
    @arg result check result holder.
    @return int !=LastBlockNumber: check sum error, *result==0. \
                ==LastBlockNumber: check sum ok, *result==1.
*/
off64_t CheckStrictryFileImage(char *b, long len, off64_t block_number, long block_size, int *result)
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
			printf("%s: Block number not match. expected(blocknumber)=%" PRId64 ", image=%" PRId64 "(0x%" PRIx64 ").\n"
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
			printf("%s: Checksum not match. blocknumber=%" PRId64 ", a=%" PRId64 "(0x%" PRIx64 ").\n"
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


/*! Mark block address on file image.
    @arg b points image buffer to write.
    @arg len length to write.
    @arg block_number block number to mark.
    @arg block_size block size.
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


/*! Fill working file up to FileSize.
    @arg fd file descriptor.
    @arg img point file image memory.
    @arg imgsize buffer byte length pointed by img.
    @arg opt Command Line option.
    @return int ==0 failed, !=0 success.
*/
int PreCreateFile(int fd, char *img, long imgsize, TCommandLineOption *opt)
{	off64_t		blockno;
	long		chunk;
	long		chunk_max;
	off64_t		startpos;
	off64_t		printpos;
	off64_t		curpos;
	off64_t		endnextpos;
	long		i;

	struct timespec	tswrite_0;
	struct timespec	tsprint;
	struct timespec	tswrite_s;
	struct timespec	tswrite_e;

	if (!img) {
		/* img is NULL. */
		printf("%s(): Internal error. buffer is not allocated.\n"
			, __func__
		);
		return(0 /* false */);
	}
	startpos=opt->BlockSize*opt->BlockStart;
	/* Seek to start position. */
	curpos=lseek64(fd,startpos,SEEK_SET);
	if (curpos<0) {
		/* seek error. */
		printf("%s: lseek64(0) failed(1). %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}

	chunk_max=opt->BlockSize*opt->BlocksMax;
	if (chunk_max>imgsize) {
		/* allocated buffer is small. */
		printf("%s(): Internal error. buffer is small. chunk_max=%ld, imgsize=%ld.\n"
			, __func__, chunk_max, imgsize
		);
		return(0 /* false */);
	}

	memset(&tswrite_0,0,sizeof(tswrite_0));
	memset(&tsprint,0,sizeof(tswrite_0));

	i=0;
	blockno=opt->BlockStart;
	curpos=startpos;
	printpos=curpos;
	endnextpos=opt->BlockSize*(opt->BlockEnd+1);

	printf("%s: Fill working file. s=%" PRId64 ", e=%" PRId64 "\n",opt->PathName,
		startpos, endnextpos-(opt->BlockSize)
	);
	/*      0123456789  0123456789  done, progress, secs */
	printf("   cur b/s,    all b/s, done, progs, secs\n");

	while (curpos<endnextpos) {
		/* loop makes working file from BlockBegin to BlockEnd. */
		off64_t		tmp;
		ssize_t		wresult;
		int		done;

		chunk=chunk_max;
		tmp=endnextpos-curpos;
		if (((off64_t)chunk)>tmp) {
			/* last chunk. */
			chunk=(long)(tmp);
		}
		if (opt->DoMark!=0) {
			MarkFileImage(img,chunk,blockno,opt->BlockSize);
		}
		clock_gettime(CLOCK_REALTIME,&tswrite_s);
		if (i==0) {
			/* Capture time at start. */
			tswrite_0=tswrite_s;
			tsprint=tswrite_s;
		}
		done=0;
		wresult=TryWrite(fd,img,chunk,&done);
		if ((!done) || (wresult!=chunk)) {
			/* Can't write requested. */
			printf("%s: write failed. wresult=0x%lx,  chunk=0x%lx. %s\n"
				,opt->PathName, (long)wresult, chunk, strerror(errno)
			);
			return(0 /* false */);
		}
		clock_gettime(CLOCK_REALTIME,&tswrite_e);
		blockno+=opt->BlocksMax;
		curpos+=chunk;
		{
			double	dt;
			double	dt_all;
			struct timespec	tsdelta;

			if (  (timespecToDouble(timespecSub(&tsdelta,&tswrite_e, &tsprint))>=1.0)
			    ||(curpos>=endnextpos)
			   ) {	/* Finish filling or elapsed 1 sec from last show. */
				dt_all=timespecToDouble(timespecSub(&tsdelta,&tswrite_e, &tswrite_0));
				dt=    timespecToDouble(timespecSub(&tsdelta,&tswrite_e, &tsprint));
				printf("%10.4e, %10.4e, %" PRId64 ", %3.2f%%, %.3f\n"
					, ((double)(curpos-printpos))/dt
					, ((double)(curpos))/dt_all
					, curpos
					, 100*(((double)(curpos-startpos))/((double)(endnextpos-startpos)))
					, dt_all
				);
				tsprint=tswrite_e;
				printpos=curpos;
			}
		}
		i++;
	}
	/* Seek to start position. */
	curpos=lseek64(fd,startpos,SEEK_SET);
	if (curpos<0) {
		/* seek error. */
		printf("%s: lseek64(0) failed(2). %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}
	return(1 /* true */);
}

#define	LARGE_FILE_SIZE	(1024L*1024L*2)

int MainTest(TCommandLineOption *opt)
{	int		result;
	int		fd;

	char		*mem;
	long		memsize;

	char		*img;
	long		imgsize;

	off64_t		end_next_pos;
	long long	area_blocks;
	long		repeats;

	long		i;
	struct timespec	ts0;
	struct stat64	st64;
	off64_t		seekto_prev;
	off64_t		seek_size;

#if (defined(MEASURE_DELAYED_READ))
	struct timespec	tstouchdone;
#endif /* (defined(MEASURE_DELAYED_READ)) */

	result=1 /* true */;
	/* Initialize random seed. */
	srand48(opt->Seed);
#if (defined(MEASURE_DELAYED_READ))
	memset(&tstouchdone,0,sizeof(tstouchdone));
#endif /* (defined(MEASURE_DELAYED_READ)) */

	{/* sub block. */
		int	flags_add;

		flags_add=0;
		if (opt->FileSize>=LARGE_FILE_SIZE) {
			flags_add|=O_LARGEFILE;
		}
		if (opt->DoDirect!=0) {
			flags_add|=O_DIRECT;
		}
		/* O_NOATIME issue error EPERM. */
		fd=open(opt->PathName
			,O_RDWR|O_CREAT /* |O_NOATIME */ |flags_add
			,S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH
		);
	}
	if (fd<0) {
		/* Can't open. */
		printf("%s: open failed. %s\n",opt->PathName,strerror(errno));
		return(0 /* false */);
	}
	if (fstat64(fd,&st64)!=0) {
		/* Can't stat. */
		printf("%s: fstat failed. %s\n",opt->PathName,strerror(errno));
		result=0 /* false */;
		goto EXIT_CLOSE;
	}
	/* allocate read buffer mem. */
	memsize=RoundUpBy((opt->BlockSize*opt->BlocksMax),ScPageSize);
	mem=mmap(NULL,memsize
		,PROT_READ|PROT_WRITE,MAP_ANONYMOUS|MAP_PRIVATE
		,-1,0);

	if (mem==MAP_FAILED) {
		printf("%s(): mmap failed(mem). %s\n",__func__,strerror(errno));
		result=0 /* false */;
		goto EXIT_CLOSE;
	}

	/* allocate write buffer img. */
	imgsize=RoundUpBy((opt->BlockSize*opt->BlocksMax)*2,ScPageSize);
	img=mmap(NULL,imgsize
		,PROT_READ|PROT_WRITE,MAP_ANONYMOUS|MAP_PRIVATE
		,-1,0);

	if (img==MAP_FAILED) {
		printf("%s(): mmap failed(img). %s\n",__func__,strerror(errno));
		result=0 /* false */;
		goto EXIT_UNMAP_MEM;
	}
	MakeFileImage(img,imgsize);
	if (opt->DoMark!=0) {
		PreMarkFileImage(img,imgsize,opt->BlockSize);
	}
	seek_size=GetFileSizeFd(fd);
	if (seek_size<0) {
		printf("%s(): lseek64 to get file size failed. %s\n",__func__,strerror(errno));
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
			printf("%s: Use option -f to set file size.\n",opt->PathName);
			result=0 /* false */;
			goto EXIT_UNMAP_IMG;
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
		} else {/* Truncate file. */
			if (ftruncate64(fd,opt->FileSize)!=0) {
				printf("%s: ftruncate64 failed. %s\n",opt->PathName,strerror(errno));
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
						printf("%s: ftruncate64 failed. %s\n",opt->PathName,strerror(errno));
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
		seek_size=opt->FileSize;
	}
	end_next_pos=opt->BlockSize*(opt->BlockEnd+1);
	area_blocks=opt->BlockEnd-opt->BlockStart+1;
	seekto_prev=-1;
	/* Record time at tests begin. */
	if (clock_gettime(CLOCK_REALTIME,&ts0)!=0) {
		printf("%s(): clock_gettime failed. %s\n",__func__,strerror(errno));
		result=0 /* false */;
		goto EXIT_UNMAP_IMG;
	}
#if (defined(MEASURE_DELAYED_READ))
	if (opt->DoMark) {
#endif /* (defined(MEASURE_DELAYED_READ)) */
		printf("i, elp, rw, pos, len, rtime, bps\n");
#if (defined(MEASURE_DELAYED_READ))
	} else {
		printf("i, elp, rw, pos, len, rtime, bps, touchtime\n");
	}
#endif /* (defined(MEASURE_DELAYED_READ)) */
	repeats=opt->Repeats;
	i=0;
	while ((i<repeats) && (result!=0)) {
		off64_t		seekto_block;
		off64_t		seekto;
		off64_t		seekto_delta;
		off64_t		seekresult;
		size_t		length;
		int		ioresult;

		struct timespec	tsrw;
		struct timespec	tsrwdone;

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
			printf("%s: seek failed. seekto=0x%.16" PRIx64 ", seekresult=0x%.16" PRIx64 ". %s\n"
				,opt->PathName,(int64_t)seekto,(int64_t)seekresult,strerror(errno)
			);
			result=0 /* false */;
			goto EXIT_UNMAP_IMG;
		}
		rw_act=((lrand48()>>16UL)&0x01UL);
		switch (opt->DoOnly) {
			case DO_ONLY_NO: {
				/* Both read and write. */
				break;
			}
			case DO_ONLY_READ: {
				/* Do Only Read. */
				/* Force read. */
				rw_act=0;
				break;
			}
			case DO_ONLY_WRITE: {
				/* Do Only Write. */
				/* Force write. */
				rw_act=1;
				break;
			}
		}
		/* Record time at read/write. */
		clock_gettime(CLOCK_REALTIME,&tsrw);
		if (rw_act==0) {
			/* Read blocks. */
			int	sum_result;
			off64_t	block_check;
			int	done;
			
			done=0;
			ioresult=TryRead(fd,mem,length,&done);
			if ((!done) || (ioresult!=length)) {
				printf("%s: read failed. %s length=0x%lx, ioresult=0x%lx.\n"
				,opt->PathName,strerror(errno),(long)length,(long)(ioresult));
				result=0 /* false */;
				goto EXIT_UNMAP_IMG;
			}
			/* Record time at touch. */
			clock_gettime(CLOCK_REALTIME,&tsrwdone);
			if (opt->DoMark!=0) {
				sum_result=0;
				block_check=CheckStrictryFileImage(
					mem,length
					,seekto_block,opt->BlockSize
					,&sum_result
				);
				if (sum_result==0) {
					/* Check sum error. */
					printf
						("%s: Check sum error. block=%" PRId64 ".\n"
						,opt->PathName
						,(int64_t)block_check
						);
					result=0;
				}
			}
#if (defined(MEASURE_DELAYED_READ))
			  else {/* Only do touch. */
				TouchSums+=TouchMemory(mem,length);
				clock_gettime(CLOCK_REALTIME,&tstouchdone);
			}
#endif /* (defined(MEASURE_DELAYED_READ)) */
			read_write='r';
		} else {/* write blocks. */
			char	*imgwork;
			int	done;
			/* Choose image to write by random. */
			imgwork=img+((opt->BlockSize)*(off64_t)(drand48()*((double)(opt->BlocksMax))));
			if (opt->DoMark) {
				MarkFileImage(imgwork,length,seekto_block,opt->BlockSize);
			}
			done=0;
			ioresult=TryWrite(fd,imgwork,length,&done);
			if ((!done) || (ioresult!=length)) {
				printf("%s: write failed. %s length=0x%lx, ioresult=0x%lx.\n"
				,opt->PathName,strerror(errno),(long)length,(long)ioresult);
				result=0 /* false */;
				goto EXIT_UNMAP_IMG;
			}
			/* Record time at touch. */
			clock_gettime(CLOCK_REALTIME,&tsrwdone);
			read_write='w';
		}
		if (seekto_prev>=0) {
			seekto_delta=seekto-seekto_prev;
		} else {
			seekto_delta=0;
		}
		
		{	double		rtime;
#if (defined(MEASURE_DELAYED_READ))
			double		touch_time;
#endif /* (defined(MEASURE_DELAYED_READ)) */
			struct timespec	tsdelta_e;
			struct timespec	tsdelta_r;
#if (defined(MEASURE_DELAYED_READ))
			struct timespec	tsdelta_t;
#endif /* (defined(MEASURE_DELAYED_READ)) */

			rtime=timespecToDouble(timespecSub(&tsdelta_r,&tsrwdone,&tsrw));
#if (defined(MEASURE_DELAYED_READ))
			if (opt->DoMark) {
#endif /* (defined(MEASURE_DELAYED_READ)) */
				/* Check marking. */
				/*       i, elp, rw, pos, len, rtime, bps */
				printf("%8ld, %10.4e, %c, 0x%.16" PRIx64 ", 0x%.8lx, %10.4e, %10.4e\n"
					,i
					,timespecToDouble(timespecSub(&tsdelta_e,&tsrw,&ts0))
					,read_write
					,(int64_t)seekto,(long)length
					,rtime
					,((double)length)/rtime
				);
#if (defined(MEASURE_DELAYED_READ))
			} else {
				/* Only touch memory. */
				touch_time=timespecToDouble(timespecSub(&tsdelta_t,&tstouchdone,&tsrwdone));
				/*       i, elp, rw, pos, len, rtime, bps, touchtime */
				printf("%8ld, %10.4e, %c, 0x%.16llx, 0x%.8lx, %10.4e, %10.4e, %10.4e\n"
					,i
					,timespecToDouble(timespecSub(&tsdelta_e,&tsrw,&ts0))
					,read_write
					,seekto,(long)length
					,rtime
					,((double)length)/rtime
					,touch_time
				);
			}
#endif /* (defined(MEASURE_DELAYED_READ)) */
		}
		seekto_prev=seekto;
		i++;
	}
EXIT_UNMAP_IMG:;
	if (munmap(img,imgsize)!=0) {
		printf("%s(): munmap failed(img). %s\n",__func__,strerror(errno));
		return(0);
	}
EXIT_UNMAP_MEM:;
	if (munmap(mem,memsize)!=0) {
		printf("%s(): munmap failed(mem). %s\n",__func__,strerror(errno));
		return(0);
	}
EXIT_CLOSE:;
	close(fd);
#if (defined(MEASURE_DELAYED_READ))
	if (opt->DoMark==0) {
		/* Skip check, only touch memory. */
		printf("TouchSums: 0x%" PRIx64 "\n",TouchSums);
	}
#endif /* (defined(MEASURE_DELAYED_READ)) */
	return(result /* true. */);
}

void show_help(void)
{	printf(
	"Command line: [-f n] [-p{y|n}] [-x{b|r|w}] [-d{y|n}] [-m{y|n}] [-b n] [-i n] [-a n] [-n n] [-s n] path_name\n"
	"-f n work file size.\n"
	"-p{y|n} Pre fill file with initial image(y: fill, n: truncate)(%c).\n"
	"-x{b|r|w} b: Do both read and write, r: Do read only, w: Do write only(%s).\n"
	"-d{y|n} Add O_DIRECT to open flags(%c).\n"
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
	,do_only_options[DEF_DoOnly]
	,(DEF_DoDirect ? 'y' : 'n')
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
		printf("%s: Test FAIL.\n",CommandLine.PathName);
		return(2);
	}
	printf("%s: Test PASS.\n",CommandLine.PathName);
	return(0);
}

