/*! ssdstress: SSD stress test tool.

   Copyright 2012 Akinori Furuta<afuruta@m7.dion.ne.jp>.
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   1. Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
   PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
   OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
   WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
   OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
   ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

#define _LARGEFILE64_SOURCE
#define _GNU_SOURCE
#include <features.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>

#include <stdint.h>
#include <inttypes.h>
#include <limits.h>

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "mt19937ar.h"

/*! ReDefile type TTimeSpec as struct timespec */
typedef	struct timespec TTimeSpec;

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

#define	DEF_FillFile		(DO_OPTION_NO)
#define	DEF_DoReadFile		(DO_READ_FILE_NO)
#define	DEF_FileSize		(0)
#define	DEF_BlockSize		(512)
#define	DEF_SequentialRWBlocks	(0)
#define	DEF_BlocksMin		(1)
#define	DEF_BlocksMax		(8192)
#define	DEF_BlockStart		(0)
#define	DEF_BlockEnd		(INT64_MAX)
#define	DEF_Repeats		(4096)
#define	DEF_Seed		(0)
#define	DEF_DoRandomAccess	(DO_RANDOM_ACCESS_BOTH)
#define	DEF_DoDirect		(DO_OPTION_YES)
#define	DEF_DoDirectRandomRW	(DO_OPTION_YES)
#define	DEF_DoMark		(DO_OPTION_YES)
#define	DEF_TestToTestSleeps	(10)

/*! Copyright notice. */
const char copyright_notice[]=
	"ssdstress: SSD stress test tool. "
	"Copyright (C) 2012 Akinori Furuta<afuruta@m7.dion.ne.jp>.\n";

/*! Command line argument holder. */
typedef struct {
	off64_t		FileSize;	/*!< -f n file size. */
	off64_t		BlockSize;	/*!< -b n block size. */
	off64_t		SequentialRWBlocks; /*!< -u n Sequential Read/Write blocks per one IO. */
	off64_t		BlocksMin;	/*!< -i n Minimum blocks to read/write. */
	off64_t		BlocksMax;	/*!< -a n Maximum blocks to read/write. */
	off64_t		BlockStart;	/*!< -o n Origin block number to test. */
	off64_t		BlockEnd;	/*!< -e n End block number to test.  */
	long		Repeats;	/*!< -n n the number of repeat random access. */
	long		Seed;		/*!< -s n random seed number. */
	char		*Argv0;		/*!< This program name. */
	char		*PathName;	/*!< Device or file path name to test. */
	int		FillFile;	/*!< Sequential Fill work file. */
	int		DoReadFile;	/*!< -r {s|y|n} Sequential Read work file. */
	int		DoRandomAccess;	/*!< -x {b|r|w} Do Random access Both r/w, Read only, Write only. */
	int		DoDirect;	/*!< -d {y|n} Do O_DIRECT io */
	int		DoDirectRandomRW; /*!< -d {Y|N} Do O_DIRECT io at random read/write. */
	int		DoMark;		  /*!< -m {y|n} Do Block Marking. */
	unsigned int	TestToTestSleeps; /*!< -t n Sleep seconds between test to test. */
} TCommandLineOption;


TCommandLineOption	CommandLine={
	.Argv0="",
	.PathName="",
	.FileSize=DEF_FileSize,
	.BlockSize=DEF_BlockSize,
	.SequentialRWBlocks=DEF_SequentialRWBlocks,
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
	.DoMark=DEF_DoMark,
	.TestToTestSleeps=DEF_TestToTestSleeps
};

/*! Accumulated number from read memory. 
    @note To avoid deep optimization.
*/
uint64_t	ReadMemorySum=0;

/*! Get CLOCK_REALTIME.
    @param p points TTimeSpec to store realtime.
    @return int !=0: Success, 0: Failed.
*/
static int TTimeSpecGetRealTime(TTimeSpec *p)
{	if (clock_gettime(CLOCK_REALTIME,p)==0) {
		return 1 /* True, Success. */;
	}
	return 0 /* False, Failed. */;
}

/*! Convert TTimeSpec to double.
    @param ts points TTimeSpec structure.
    @return double second.
*/
double TTimeSpecToDouble(const TTimeSpec *ts)
{	if (!ts) {
		return 0.0;
	}
	return((double)(ts->tv_sec)+(ts->tv_nsec)/(1000.0*1000.0*1000.0));
}

/*! Sub two TTimeSpec(s), *y=*a-*b.
    @param y points TTimeSpec structure to store *a-*b
    @param a points TTimeSpec structure.
    @param b points TTimeSpec structure.
    @return struct TTimeSpec pointer equal to y.
    @note *a means end time, *b means start time.
*/
TTimeSpec *TTimeSpecSub(TTimeSpec *y, const TTimeSpec *a, const TTimeSpec *b)
{	time_t	sec;
	long	nsec;

	sec= a->tv_sec- b->tv_sec;
	nsec=a->tv_nsec-b->tv_nsec;
	if (nsec<0) {
		/* Borrow */
		sec--;
		nsec+=1000L*1000L*1000L;
	}
	y->tv_sec=sec;
	y->tv_nsec=nsec;
	return(y);
}

/*! Sub two TTimeSpec(s), ((double)result)=*a-*b.
    @param a points TTimeSpec structure.
    @param b points TTimeSpec structure.
    @return double delta time of *a-*b in double.
    @note *a means end time, *b means start time.
*/
double TTimeSpecSubDouble(const TTimeSpec *a, const TTimeSpec *b)
{	time_t	sec;
	long	nsec;

	sec= a->tv_sec- b->tv_sec;
	nsec=a->tv_nsec-b->tv_nsec;
	if (nsec<0) {
		/* Borrow */
		sec--;
		nsec+=1000L*1000L*1000L;
	}
	return ((double)(sec))+((nsec)/(1000.0*1000.0*1000.0));
}


/*! Zero TTimeSpec.
    @param y points TTimeSpec structure.
*/
void TTimeSpecZero(TTimeSpec *y)
{	if (!y) {
		return;
	}
	y->tv_sec=0;
	y->tv_nsec=0;
}

/*! Add two TTimeSpec(s), *y=*a+*b.
    @param y points TTimeSpec structure to store *a+*b
    @param a points TTimeSpec structure.
    @param b points TTimeSpec structure.
    @return struct TTimeSpec pointer equal to y.
*/
TTimeSpec *TTimeSpecAdd(TTimeSpec *y, const TTimeSpec *a, const TTimeSpec *b)
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
    @param a  value to round up, should be a>0.
    @param by round step value, should be b>0.
    @return long long rounded value.
*/
long long RoundUpBy(long long a, long long by)
{	long long	t;

	if (by==0) {
		/* avoid zero divide. */
		return(a);
	}
	t=a+by-1;
	return(t-(t%by));
}

/*! string to unsigned long long with suffix.
    @param p  points char array to parse human readable unsigned long long number.
    @param p2 points char* to store pointer at stopping parse.
    @param radix default radix to parse.
    @return unsigned long long parsed number.
*/
unsigned long long StrToULLKmg(char *p, char **p2, int radix)
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
	ptmp=NULL;
	a=strtoul(p,&ptmp,radix);
	if (p==ptmp) {
		*p2=p;
		return(0);
	}
	p=ptmp;
	switch (*p) {
		case 'k': 
		case 'K': {
			/* Kilo */
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

		case 'p': 
		case 'P': {
			/* Peta */
			p++;
			a*=1024ULL*1024ULL*1024ULL*1024ULL*1024ULL;
			break;
		}
	}
	*p2=p;
	return(a);
}

#define TRY_WRITE_MAX	(10)

/*! Try write.
    Continue write, until all requested bytes are written.
    @param fd  file descriptor to write bytes.
    @param b   points byte array to write.
    @param len bytes to write.
    @param done points int variable to store success(!=0) or failed(==0).
    @return ssize_t written bytes.
*/
ssize_t TryWrite(int fd, const unsigned char *b, size_t len, int *done)
{	ssize_t		wresult;
	ssize_t		remain;
	int		try_count;
	int		done_dummy;
	
	if (!done) {
		/* Need dummy. */
		done=&done_dummy;
	}
	*done=1; /* True: means all bytes are written. */
	try_count=0;
	remain=len;
	while ((remain>0) && (try_count<TRY_WRITE_MAX)) {
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
			printf("fd=%d: Too small write progress. remain=%lld, wresult=%lld, try_count=%d\n",
				fd, (long long)remain, (long long)wresult, try_count
			);
			/* yeld other thread. */
			ts_req.tv_sec=0;
			ts_req.tv_nsec=1000L*1000L;
			nanosleep(&ts_req, NULL);
		}
		b+=wresult;
		try_count++;
	}
	if (remain>0) {
		/* Too many retries, but remain un written bytes. */
		*done=0;
	}
	return(((ssize_t)len)-remain);
}

#define TRY_READ_MAX	(10)

/*! Try read.
    Continue read, until all requested bytes are read or EOF.
    @param fd  file descriptor to read bytes.
    @param b   points byte array to store reads.
    @param len bytes to read.
    @param done points int variable to store success(!=0) or failed(==0).
    @return ssize_t read bytes.
*/
ssize_t TryRead(int fd, unsigned char *b, size_t len, int *done)
{	ssize_t		rresult;
	ssize_t		remain;
	int		try_count;
	int		done_dummy;

	if (!done) {
		/* Need dummy. */
		done=&done_dummy;
	}
	*done=1; /* True: means all bytes are written. */
	try_count=0;
	remain=len;
	while ((remain>0) && (try_count<TRY_WRITE_MAX)) {
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
			printf("fd=%d: Too small read progress. remain=%lld, rresult=%lld, try_count=%d\n",
				fd, (long long)remain, (long long)rresult, try_count
			);
			/* yeld other thread. */
			ts_req.tv_sec=0;
			ts_req.tv_nsec=1000L*1000L;
			nanosleep(&ts_req, NULL);
		}
		b+=rresult;
		try_count++;
	}
	if (remain>0) {
		/* Too many retries, but remain un read bytes. */
		*done=0;
	}
	return(((ssize_t)len)-remain);
}

/*! Dump bytes per line. Should be power of 2. */
#define DUMP_BYTES_PER_LINE	(0x10)

/*! Dump memory image.
    @param buf    points memory to HEX dump.
    @param n      number of bytes to dump.
    @param offset meaning offset address pointed by buf.
    @return const unsigned char* argument buf + n.
*/
const unsigned char *DumpMemory(const unsigned char *buf, long long n, long long offset)
{	long long	cntr;

	printf("%.16llx ",offset&((~0LL)-(DUMP_BYTES_PER_LINE-1)));
	cntr=offset&(DUMP_BYTES_PER_LINE-1);
	while (cntr>0) {
		/* Fill upto offset to start dump. */
		printf("-- ");
		cntr--;
	}

	cntr=offset&(DUMP_BYTES_PER_LINE-1);
	while (n>0) {
		/* Loop until all bytes are dumped. */
		cntr++;
		n--;
		/* Step next offset. */
		offset++;
		if (cntr>=DUMP_BYTES_PER_LINE) {
			/* End of colums. */
			if (n>0) {
				/* More dump lines. */
				printf("%.2x\n%.16llx ",*buf,offset);
			} else {
				/* No more dump lines. */
				printf("%.2x\n",*buf);
			}
			cntr=0;
		} else {
			/* Continue colums. */
			if (n>0) {
				/* Will be continue. */
				printf("%.2x ",*buf);
			} else {
				/* End of dump. */
				printf("%.2x\n",*buf);
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
int TCommandLineOptionGetopt(TCommandLineOption *opt, char argc, char **argv0)
{	char	*p;
	char	*p2;
	int	c;
	int	result;
	int	opt_e;

	result=1;
	opt->Argv0=*argv0;

	while ((c=getopt(argc,argv0,"b:u:f:p:r:x:d:m:i:a:o:e:n:s:z:h"))!=-1) {
		switch (c) {
			case 'b': { /* -b block_size */
				const char error_message[]="-b: Error: Need block size by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					off64_t	save;
					save=opt->BlockSize;
					opt->BlockSize=StrToULLKmg(p,&p2,0);
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
			case 'u': {
				/* -u Sequential read/write blocks per one call. */
				const char error_message[]="-u: Error: Need Sequential read/write blocks per one IO by number[k|m|g|t|]\n";
				p=optarg;
				if (p) {
					off64_t	save;
					save=opt->SequentialRWBlocks;
					opt->SequentialRWBlocks=StrToULLKmg(p,&p2,0);
					if (opt->BlockSize<=0) {
						/* Zero or negative BlockSize. */
						opt->SequentialRWBlocks=save;
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
					opt->FileSize=StrToULLKmg(p,&p2,0);
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
					opt->BlocksMin=StrToULLKmg(p,&p2,0);
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
					opt->BlocksMax=StrToULLKmg(p,&p2,0);
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
					opt->BlockStart=StrToULLKmg(p,&p2,0);
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
					opt->BlockEnd=StrToULLKmg(p,&p2,0);
					opt_e=1;
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'n': { /* -n repeat counts. */
				const char error_message[]="-n: Error: Need repeat counts by number.\n";
				p=optarg;
				if (p) {
					opt->Repeats=StrToULLKmg(p,&p2,0);
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
					opt->Seed=StrToULLKmg(p,&p2,0);
				} else {
					printf(error_message);
					result=0;
				}
				break;
			}
			case 'z': { /* -z sleep time after test. */
				const char error_message[]="-z: Error: Need sleep time in seconds by number.\n";
				p=optarg;
				if (p) {
					unsigned long long t;
					t=StrToULLKmg(p,&p2,0);
					if (t>UINT_MAX) {
						t=UINT_MAX;
					}
					opt->TestToTestSleeps=(unsigned int)t;
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
		printf("%s: Error: need working file path. PathName=NULL\n", *argv0);
		result=0;
	}
	if (opt->BlockSize<(sizeof(off64_t)*3)) {
		printf("%s: -b %" PRId64 ": Error: Should be more than %lu.\n",*argv0, (int64_t)(opt->BlockSize), (unsigned long)(sizeof(off64_t)*3));
		result=0;
	}
	if ((opt->BlockSize%(sizeof(off64_t)))!=0) {
		printf("%s: -b %" PRId64 ": Error: Should be divided by %lu.\n",*argv0, (int64_t)(opt->BlockSize), (unsigned long)(sizeof(off64_t)));
		result=0;
	}
	if (opt->SequentialRWBlocks<=0) {
		opt->SequentialRWBlocks=opt->BlocksMax*2;
	}
	opt->FileSize=RoundUpBy(opt->FileSize,opt->BlockSize);
	return(result /* true */);
}

const char	*do_only_options[]={"b","r","w"};
const char	*do_read_file_options[]={"n","y","s"};

/*! Show command line arguments.
    @param p points TCommandLineOption structure to show.
    @return void nothing.
*/
void TCommandLineOptionShow(TCommandLineOption *opt)
{	printf	("BuildDate: %s\n"
		,__DATE__
	);
	printf
		("PathName: %s\n"
		 "FileSize(-f): %" PRId64 "\n"
		 "FillFile(-p): %c\n"
		 "DoRandomAccess(-x): %s\n"
		 "DoReadFile(-r): %s\n"
		 "DoDirect(-d): %c%c\n"
		 "DoMark(-m): %c\n"
		 "BlockSize(-b): %" PRId64 "\n"
		 "SequentialRWBlocks(-u): %" PRId64 "\n"
		 "BlocksMin(-i): %" PRId64 "\n"
		 "BlocksMax(-a): %" PRId64 "\n"
		 "BlockStart(-o): %" PRId64 "\n"
		 "BlockEnd(-e): %" PRId64 "\n"
		 "Repeats(-n): %ld\n"
		 "Seed(-s): %ld\n"
		 "WaitTime(-z): %u\n"
		 ,opt->PathName
		 ,(int64_t)(opt->FileSize)
		 ,(opt->FillFile ? 'y' : 'n')
		 ,do_only_options[opt->DoRandomAccess]
		 ,do_read_file_options[opt->DoReadFile]
		 ,(opt->DoDirect ? 'y' : 'n')
		 ,(opt->DoDirectRandomRW ? 'Y' : 'N')
		 ,(opt->DoMark ? 'y' : 'n')
		 ,(int64_t)(opt->BlockSize)
		 ,(int64_t)(opt->SequentialRWBlocks)
		 ,(int64_t)(opt->BlocksMin)
		 ,(int64_t)(opt->BlocksMax)
		 ,(int64_t)(opt->BlockStart)
		 ,(int64_t)(opt->BlockEnd)
		 ,opt->Repeats
		 ,opt->Seed
		 ,opt->TestToTestSleeps
		);
}

/*! Read memory stepping by page size, to make sure read data from device.
    @param b points buffer.
    @param len buffer length pointed by b.
    @return unsigned long summing up value.
*/
uint64_t ReadMemoryStepByPage(const unsigned char *b, long len)
{	uint64_t	a;
	long		ps;

	a=0;
	ps=ScPageSize;

	while (len>0) {
		/* Read some bytes from buffer. Stepping by ScPageSize.*/
		a+=*(uint64_t*)b;
		b+=ps;
		len-=ps;
	}
	return(a);
}

/*! Write memory stepping by page size, to make sure buffer area is placed \
    on main memory and invalidate block number mark.
    @param b points buffer.
    @param len buffer length pointed by b.
    @return unsigned long summing up value.
*/
void WriteMemoryStepByPage(unsigned char *b, long len)
{	uint64_t	a;
	long		ps;

	a=0;
	ps=ScPageSize;
	while (len>0) {
		/* Write bytes to buffer. Stepping by ScPageSize.*/
		*(uint64_t*)b=a;
		b+=ps;
		len-=ps;
	}
}

/*! Get file size using lseek64.
    @param fd file descriptor to get file size.
    @return off64_t file size, <0: failed.
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
		if (lseek64(fd,cur,SEEK_SET)<0) {
			/* ignore error. */
			printf("fd=%d: Notice: Can not rewind file position. %s(%d).\n", fd, strerror(errno), errno);
		}
	}
	return(size);
}

/*! Fill random to file image memory.
    @param b    points file image buffer to fill random, will be marked and written to file.
    @param len  buffer length in bytes pointed by b.
*/
void FillRandomFileImage(unsigned char *b, long len)
{	while (len>0) {
		*((uint32_t*)b)=genrand_uint32();
		b+=sizeof(uint32_t);
		len-=sizeof(uint32_t);
	}
}

/*! Pre mark block address on file image memory.
    @param b0 points file image buffer to mark, will be written to file.
    @param len0 buffer length in bytes pointed by b0.
    @param blocksize block size.
*/
void PreMarkFileImage(unsigned char *b0, long len0, long blocksize)
{
	unsigned char		*b;
	long			count;
	long			len;
	off64_t			a;

	len=len0;
	b=b0;
	a=0;
	while (len>0) {
		/* Zero block number and check sum area. */
		*(((off64_t *)b)+0)=a;
		*(((off64_t *)b)+1)=a;
		*((off64_t *)(b+blocksize-sizeof(a)))=a;
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
		while (count>0) {
			/* Summimg up image by u64. */
			a+=*((off64_t*)b);
			b+=sizeof(a);
			count-=sizeof(a);
		}
		/* Mark last u64 with complement. */
		*((off64_t*)(b-sizeof(a)))=-a;
		len-=blocksize;
	}
}

/*! Strictly check file image on memory.
    @param b0 points file image buffer to check.
    @param len0 buffer length pointed by b0.
    @param block_number image block number pointed by b0.
    @param block_size block size.
    @param result check result holder.
    @return int !=LastBlockNumber: check sum error, *result==0. \
                ==LastBlockNumber: check sum ok, *result==1.
*/
off64_t CheckStrictlyFileImage(unsigned char *b, long len, off64_t block_number, long block_size, int *result)
{
	long			count;
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
		while (count>0) {
			/* Summimg up image by u64. */
			a+=*((off64_t*)b);
			b+=sizeof(a);
			count-=sizeof(a);
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
off64_t CheckLightFileImage(unsigned char *b, long len, off64_t block_number, long block_size, int *result)
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
void MarkFileImage(unsigned char *b, long len, off64_t block_number, off64_t block_size)
{	off64_t		a;
	uint64_t	r;

	while (len>0) {
		r =((uint64_t)genrand_uint32())<<(uint64_t) 0;
		r|=((uint64_t)genrand_uint32())<<(uint64_t)32;

		a= *(((off64_t*)b)+0)
		  +*(((off64_t*)b)+1);

		*(((off64_t*)b)+1)=r;
		*(((off64_t*)b)+0)=block_number-r;
		*((off64_t*)(b-sizeof(a)+block_size))-=block_number-a;
		block_number++;
		b+=block_size;
		len-=block_size;
	}
}


/*! Fill(Write) working file up to FileSize.
    @param fd file descriptor.
    @param img point file image memory.
    @param img_size buffer byte length pointed by img.
    @param opt Command Line option.
    @return int ==0 failed, !=0 success.
*/
int FillWriteFile(int fd, unsigned char *img, long img_size, TCommandLineOption *opt)
{	off64_t		block_no;
	long		chunk;
	long		chunk_max;
	off64_t		start_pos;
	off64_t		print_pos;
	off64_t		cur_pos;
	off64_t		end_next_pos;

	TTimeSpec	ts_write_0;
	TTimeSpec	ts_print;
	TTimeSpec	ts_write_s;
	TTimeSpec	ts_write_e;
	TTimeSpec	ts_write_e_tmp;
	TTimeSpec	ts_write_ap;
	TTimeSpec	ts_write_aa;
	TTimeSpec	ts_mem_a;

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
		printf("%s: Error: lseek64(0) failed at init. %s(%d)\n",opt->PathName, strerror(errno),errno);
		return(0 /* false */);
	}

	chunk_max=opt->BlockSize*opt->SequentialRWBlocks;
	if (chunk_max>img_size) {
		/* allocated buffer is small. */
		printf("%s(): Error: Internal, buffer is small. chunk_max=%ld, img_size=%ld.\n"
			, __func__, chunk_max, img_size
		);
		return(0 /* false */);
	}

	TTimeSpecZero(&ts_write_ap);
	TTimeSpecZero(&ts_write_aa);
	TTimeSpecZero(&ts_mem_a);

	block_no=opt->BlockStart;
	cur_pos=start_pos;
	print_pos=cur_pos;
	end_next_pos=opt->BlockSize*(opt->BlockEnd+1);

	printf("%s: Info: Fill working file. s=%" PRId64 ", e=%" PRId64 "\n",opt->PathName,
		start_pos, end_next_pos-(opt->BlockSize)
	);
	/*      0123456789  0123456789  0123456789  0123456789  cur_pos progress, Twrite, Twrite_total, Twrite_elapsed, Telapsed, Tmem_access_total */
	printf("   cur b/s,  total b/s, cur_el b/s,    elp b/s, cur_pos, progs, Twrite, Twrite_total, Twrite_elapsed, Telapsed, Tmem_access_total\n");

	if (!TTimeSpecGetRealTime(&ts_write_0)) {
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
		double		dt_write_elp;

		chunk=chunk_max;
		tmp=end_next_pos-cur_pos;
		if (((off64_t)chunk)>tmp) {
			/* last chunk. */
			chunk=(long)(tmp);
		}
		if (opt->DoMark!=0) {
			/* Do mark block number. */
			MarkFileImage(img,chunk,block_no,opt->BlockSize);
		}
		done=0;
		TTimeSpecGetRealTime(&ts_write_s);
		wresult=TryWrite(fd,img,chunk,&done);
		TTimeSpecGetRealTime(&ts_write_e_tmp);
		if ((!done) || (wresult!=chunk)) {
			/* Can't write requested. */
			printf("%s: Error: Write failed. wresult=0x%lx,  chunk=0x%lx. %s(%d)\n"
				,opt->PathName, (long)wresult, chunk, strerror(errno), errno
			);
			return(0 /* false */);
		}

		TTimeSpecAdd(&ts_mem_a,&ts_mem_a,&ts_write_s);
		TTimeSpecSub(&ts_mem_a,&ts_mem_a,&ts_write_e);
		TTimeSpecAdd(&ts_write_aa,&ts_write_aa,&ts_write_e_tmp);
		TTimeSpecSub(&ts_write_aa,&ts_write_aa,&ts_write_s);
		ts_write_e=ts_write_e_tmp;

		block_no+=opt->SequentialRWBlocks;
		cur_pos+=chunk;
		
		dt_write_elp=TTimeSpecSubDouble(&ts_write_e_tmp, &ts_print);
		if (  (dt_write_elp>=1.0)
		    ||(cur_pos>=end_next_pos)
		   ) {	/* Finish filling or elapsed 1 sec from last show. */
			double		dt_write;
			double		dt_all;
			double		dt_mem;
			double		dt_elp;
			double		print_pos_delta;
			double		pos_delta;

			dt_write=TTimeSpecSubDouble(&ts_write_aa, &ts_write_ap);
			dt_all=TTimeSpecToDouble(&ts_write_aa);
			dt_elp=TTimeSpecSubDouble(&ts_write_e_tmp, &ts_write_0);
			dt_mem=TTimeSpecToDouble(&ts_mem_a);
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
	/* Seek to start position. */
	cur_pos=lseek64(fd,start_pos,SEEK_SET);
	if (cur_pos<0) {
		/* seek error. */
		printf("%s: Error: lseek64(0) failed at done. %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}
	return(1 /* true */);
}

/*! Read working file up to FileSize.
    @param path 
    @param fd file descriptor.
    @param img point file image memory.
    @param img_size buffer byte length pointed by img.
    @param opt Command Line option.
    @return int ==0 failed, !=0 success.
*/
int ReadFile(int fd, unsigned char *img, long img_size, TCommandLineOption *opt)
{	off64_t		block_no;
	long		chunk;
	long		chunk_max;
	off64_t		start_pos;
	off64_t		print_pos;
	off64_t		cur_pos;
	off64_t		end_next_pos;

	TTimeSpec	ts_read_0;
	TTimeSpec	ts_print;
	TTimeSpec	ts_read_s;
	TTimeSpec	ts_read_e;
	TTimeSpec	ts_read_e_tmp;
	TTimeSpec	ts_read_ap;
	TTimeSpec	ts_read_aa;
	TTimeSpec	ts_mem_a;

	if (!img) {
		/* img is NULL. */
		printf("%s(): Error: Internal, buffer is not allocated.\n"
			, __func__
		);
		return(0 /* false */);
	}
	start_pos=(opt->BlockSize)*(opt->BlockStart);
	/* Seek to start position. */
	cur_pos=lseek64(fd,start_pos,SEEK_SET);
	if (cur_pos<0) {
		/* seek error. */
		printf("%s: Error: lseek64(0) failed at init. %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}

	chunk_max=(opt->BlockSize)*(opt->SequentialRWBlocks);
	if (chunk_max>img_size) {
		/* allocated buffer is small. */
		printf("%s(): Error: Internal, buffer is small. chunk_max=%ld, img_size=%ld.\n"
			, __func__, chunk_max, img_size
		);
		return(0 /* false */);
	}

	/* Write memory to place buffer on main memory. */
	WriteMemoryStepByPage(img,img_size);

	TTimeSpecZero(&ts_read_ap);
	TTimeSpecZero(&ts_read_aa);
	TTimeSpecZero(&ts_mem_a);

	block_no=opt->BlockStart;
	cur_pos=start_pos;
	print_pos=cur_pos;
	end_next_pos=opt->BlockSize*(opt->BlockEnd+1);

	printf("%s: Info: Read working file. s=%" PRId64 ", e=%" PRId64 "\n",opt->PathName,
		start_pos, end_next_pos-(opt->BlockSize)
	);
	/*      0123456789  0123456789  0123456789  0123456789 cur_pos progress, Tread, Tread_total, Tread_elapsed, Telapsed, Tmem_access_total, */
	printf("   cur b/s,  total b/s, cur_el b/s,    elp b/s, cur_pos, progs, Tread, Tread_total, Tread_elapsed, Telapsed, Tmem_access_total\n");

	TTimeSpecGetRealTime(&ts_read_0);
	ts_read_e=ts_read_0;
	ts_print= ts_read_0;
	while (cur_pos<end_next_pos) {
		/* loop makes working file from BlockBegin to BlockEnd. */
		off64_t		tmp;
		ssize_t		rresult;
		int		done;
		double		dt_read_elp;

		chunk=chunk_max;
		tmp=end_next_pos-cur_pos;
		if (((off64_t)chunk)>tmp) {
			/* last chunk. */
			chunk=(long)(tmp);
		}
		done=0;
		TTimeSpecGetRealTime(&ts_read_s);
		rresult=TryRead(fd,img,chunk,&done);
		TTimeSpecGetRealTime(&ts_read_e_tmp);
		if ((!done) || (rresult!=chunk)) {
			/* Can't write requested. */
			printf("%s: Error: Read failed. rresult=0x%lx,  chunk=0x%lx. %s\n"
				,opt->PathName, (long)rresult, chunk, strerror(errno)
			);
			return(0 /* false */);
		}
		TTimeSpecAdd(&ts_mem_a,&ts_mem_a,&ts_read_s);
		TTimeSpecSub(&ts_mem_a,&ts_mem_a,&ts_read_e);
		TTimeSpecAdd(&ts_read_aa,&ts_read_aa,&ts_read_e_tmp);
		TTimeSpecSub(&ts_read_aa,&ts_read_aa,&ts_read_s);
		ts_read_e=ts_read_e_tmp;

		if (opt->DoMark!=0) {
			/* Marked block. */
			int		r;
			off64_t		block_check;
			r=0;
			switch (opt->DoReadFile) {
				case DO_READ_FILE_LIGHT:
					block_check=CheckLightFileImage(img, chunk, block_no, opt->BlockSize, &r);
					break;
				case DO_READ_FILE_STRICT:
					block_check=CheckStrictlyFileImage(img, chunk, block_no, opt->BlockSize, &r);
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
			ReadMemorySum+=ReadMemoryStepByPage(img,chunk);
		}

		block_no+=opt->SequentialRWBlocks;
		cur_pos+=chunk;
		dt_read_elp=TTimeSpecSubDouble(&ts_read_e_tmp, &ts_print);
		if (  (dt_read_elp>=1.0)
		    ||(cur_pos>=end_next_pos)
		   ) {	/* Finish filling or elapsed 1 sec from last show. */
			double		dt_read;
			double		dt_all;
			double		dt_mem;
			double		dt_elp;

			double		print_pos_delta;
			double		pos_delta;

			dt_read=TTimeSpecSubDouble(&ts_read_aa,&ts_read_ap);
			dt_all= TTimeSpecToDouble(&ts_read_aa);
			dt_elp= TTimeSpecSubDouble(&ts_read_e_tmp, &ts_read_0);
			dt_mem= TTimeSpecToDouble(&ts_mem_a);
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
	/* Seek to start position. */
	cur_pos=lseek64(fd,start_pos,SEEK_SET);
	if (cur_pos<0) {
		/* seek error. */
		printf("%s: Error: lseek64(0) failed at done. %s\n",opt->PathName, strerror(errno));
		return(0 /* false */);
	}
	return(1 /* true */);
}

/*! Random read/write working file.
    @param fd file descriptor.
    @param img point file image memory to write.
    @param img_size buffer byte length pointed by img.
    @param img_locked 0: write buffer without lock, 1: write buffer with lock.
    @param mem point file image memory to read.
    @param mem_size buffer byte length pointed by mem.
    @param mem_locked 0: read buffer without lock, 1: read buffer with lock.
    @param opt Command Line option.
    @return int ==0 failed, !=0 success.

*/
int RandomRWFile(int fd, unsigned char *img, long img_size, char img_locked
		,unsigned char *mem, long mem_size, char mem_locked
		,TCommandLineOption *opt
	)
{	off64_t		seek_size;
	off64_t		end_next_pos;
	off64_t		area_blocks;
	long		repeats;
	long		i;
	int		result;
	double		rw_time_max;
	unsigned int	sleeps_prefer;

	TTimeSpec	ts_0;
	TTimeSpec	ts_mem_delta;
	TTimeSpec	ts_rw_delta;
	TTimeSpec	ts_op_done;

	result=1;
	seek_size=GetFileSizeFd(fd);
	end_next_pos=opt->BlockSize*(opt->BlockEnd+1);
	area_blocks=opt->BlockEnd-opt->BlockStart+1;
	printf("%s: Info: Random access working file. s=%" PRId64 ", e=%" PRId64 "\n",opt->PathName,
		opt->BlockStart*opt->BlockSize, end_next_pos-(opt->BlockSize)
	);
	rw_time_max=0;
	/* Record time at tests begin. */
	if (!TTimeSpecGetRealTime(&ts_0)) {
		printf("%s(): Error: clock_gettime failed. %s\n",__func__,strerror(errno));
		return 0; /* failed */
	}
	printf("index, elp, rw, pos, len, access_time, bps, memory_access_time\n");
	repeats=opt->Repeats;
	i=0;
	while ((i<repeats) && (result!=0)) {
		off64_t		seek_to_block;
		off64_t		seek_to;
		off64_t		seek_result;
		size_t		length;
		int		ioresult;

		TTimeSpec	ts_mem;
		TTimeSpec	ts_rw_start;
		TTimeSpec	ts_rw_done;

		char		read_write;
		unsigned char	rw_act;

		double		rw_time;
		double		mem_time;
		TTimeSpec	ts_elapsed;

		/* Calc random seek position and size. */
		seek_to_block=(off64_t)(genrand_real2()*(double)area_blocks)+opt->BlockStart;
		seek_to=(opt->BlockSize)*seek_to_block;
		length=(opt->BlockSize)*((long)(genrand_real2()*(double)(opt->BlocksMax-opt->BlocksMin+1))+opt->BlocksMin);
		if ((length+seek_to)>end_next_pos) {
			/* over runs at block end. */
			length=end_next_pos-seek_to;
		}
		if ((length+seek_to)>seek_size) {
			/* over runs at end of file. */
			length=seek_size-seek_to;
		}
		/* Seek random. */
		seek_result=lseek64(fd,seek_to,SEEK_SET);
		if (seek_result<0) {
			printf("%s: Error: seek failed. seek_to=0x%.16" PRIx64 ", seek_result=0x%.16" PRIx64 ". %s\n"
				,opt->PathName,(int64_t)seek_to,(int64_t)seek_result,strerror(errno)
			);
			return 0; /* failed */
		}
		rw_act=genrand_uint32()&0x01UL;
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
			default: {
				/* Unexpected value. */
				printf("%s: Error: Internal, unexpected DoRandomAccess value. DoRandomAccess=%d\n"
					,__func__
					,opt->DoRandomAccess
				);
				return 0;
			}
		}
		if (rw_act==0) {
			/* Read blocks. */
			int	sum_result;
			off64_t	block_check;
			int	done;

			if (length>mem_size) {
				printf("%s: Error: Internal, allocated buffer shorter than needed. length=%lx, mem_size=%lx\n"
					, opt->Argv0, length, mem_size
				);
				return 0; /* failed */
			}
			if (mem_locked==0) {
				/* Read buffer is unlocked. */
				/* Write memory to place buffer on main memory. */
				WriteMemoryStepByPage(mem,length);
			}
			done=0;
			/* Record time at read. */
			TTimeSpecGetRealTime(&ts_rw_start);
			ioresult=TryRead(fd,mem,length,&done);
			/* Record time at done read. */
			TTimeSpecGetRealTime(&ts_rw_done);
			if ((!done) || (ioresult!=length)) {
				printf("%s: Error: read failed. %s length=0x%lx, ioresult=0x%lx.\n"
				,opt->PathName,strerror(errno),(long)length,(long)(ioresult));
				return 0; /* failed */
			}
			if (opt->DoMark!=0) {
				sum_result=0;
				block_check=CheckStrictlyFileImage(
					mem,length
					,seek_to_block,opt->BlockSize
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
				ReadMemorySum+=ReadMemoryStepByPage(mem,length);
			}
			TTimeSpecGetRealTime(&ts_mem);
			TTimeSpecSub(&ts_rw_delta,&ts_rw_done,&ts_rw_start);
			TTimeSpecSub(&ts_mem_delta,&ts_mem,&ts_rw_done);
			ts_op_done=ts_mem;
			read_write='r';
		} else {/* write blocks. */
			unsigned char	*img_work;
			int		done;
			off64_t		img_offset;

			TTimeSpecGetRealTime(&ts_mem);
			/* Choose image to write by random. */
			img_offset=(opt->BlockSize)*(off64_t)(genrand_real2()*((double)(opt->BlocksMax)));
			img_work=img+img_offset;
			if (opt->DoMark) {
				/* Do block number marking. */
				MarkFileImage(img_work,length,seek_to_block,opt->BlockSize);
			}
			if ((img_offset+length)>img_size) {
				printf("%s: Error: Internal, allocated buffer shorter than needed. length=%lx, img_size=%lx\n"
					, opt->Argv0, length, img_size
				);
				return 0; /* failed */
			}
			done=0;
			TTimeSpecGetRealTime(&ts_rw_start);
			ioresult=TryWrite(fd,img_work,length,&done);
			/* Record time at touch. */
			TTimeSpecGetRealTime(&ts_rw_done);
			if ((!done) || (ioresult!=length)) {
				printf("%s: Error: write failed. %s length=0x%lx, ioresult=0x%lx.\n"
				,opt->PathName,strerror(errno),(long)length,(long)ioresult);
				return 0;
			}
			TTimeSpecSub(&ts_rw_delta,&ts_rw_done,&ts_rw_start);
			TTimeSpecSub(&ts_mem_delta,&ts_rw_start,&ts_mem);
			ts_op_done=ts_rw_done;
			read_write='w';
		}

		rw_time=TTimeSpecToDouble(&ts_rw_delta);
		mem_time=TTimeSpecToDouble(&ts_mem_delta);
		/*       i, elp, rw, pos, len, rw_time, bps, touchtime */
		printf("%8ld, %10.4e, %c, 0x%.16" PRIx64 ", 0x%.8lx, %10.4e, %10.4e, %10.4e\n"
			,i
			,TTimeSpecToDouble(TTimeSpecSub(&ts_elapsed,&ts_op_done,&ts_0))
			,read_write
			,seek_to
			,(long)length
			,rw_time
			,((double)length)/rw_time
			,mem_time
		);
		if (rw_time_max<rw_time) {
			/* Update max random access time. */
			rw_time_max=rw_time;
		}
		i++;
	}
	/* Estimate sleep time before start next test. */
	sleeps_prefer=(unsigned int)(rw_time_max*2.0);
	if (sleeps_prefer>opt->TestToTestSleeps) {
		/* More sleeps needed before start next test. */
		opt->TestToTestSleeps=sleeps_prefer;
	}
	return result;
}

#define	LARGE_FILE_SIZE	(1024L*1024L*2)

/*! Test main read/write part.
    @param img        points random write buffer and sequential read/write buffer.
    @param img_size   byte size of buffer pointed by img.
    @param img_locked 0: unlocked write buffer, 1: locked write buffer.
    @param mem        points random read buffer.
    @param mem_size   byte size of buffer pointed by mem.
    @param mem_locked 0: unlocked read buffer, 1: locked read buffer.
    @param opt        command line option.
    @return int       !=0: Success, ==0: Failed.
*/
int MainTestRW(unsigned char *img, long img_size, char img_locked
	      ,unsigned char *mem, long mem_size, char mem_locked
	      ,TCommandLineOption *opt
	)
{	int		result;
	int		fd;
	int		flags;
	int		fd_flags_base;
	int		fd_flags_add_seq;
	int		fd_flags_add_random;

	struct stat64	st64;
	off64_t		seek_size;

	result=1 /* true */;

	/* Sequential write part. */
	/* O_NOATIME issue error EPERM. */
	fd_flags_base=O_RDWR | O_CREAT /* | O_NOATIME */;

	if (opt->FileSize>=LARGE_FILE_SIZE) {
		fd_flags_base|=O_LARGEFILE;
	}

	fd_flags_add_seq=0;
	if (opt->DoDirect!=0) {
		fd_flags_add_seq|=O_DIRECT;
	}
	flags=fd_flags_base | fd_flags_add_seq;

	fd=open(opt->PathName
		,flags
		,S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
	);
	if (fd<0) {
		/* Can't open. */
		printf("%s: Error: open() failed. %s(%d)\n",opt->PathName,strerror(errno), errno);
		return(0 /* false */);
	}
	printf("%s: Info: open. fd=%d, flags=0x%x, time=%" PRId64 "\n",opt->PathName, fd, flags, (int64_t)time(0));
	if (fstat64(fd,&st64)!=0) {
		/* Can't stat. */
		printf("%s: Error: fstat64() failed. %s(%d)\n",opt->PathName,strerror(errno), errno);
		result=0 /* false */;
		goto EXIT_CLOSE_ERROR;
	}

	seek_size=GetFileSizeFd(fd);
	if (seek_size<0) {
		printf("%s(): Error: lseek64() to get file size failed. %s(%d)\n",__func__,strerror(errno), errno);
		result=0 /* false */;
		goto EXIT_CLOSE_ERROR;
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
			goto EXIT_CLOSE_ERROR;
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
			if (!FillWriteFile(fd,img,img_size,opt)) {
				/* Fail to create. */
				result=0 /* false */;
				goto EXIT_CLOSE_ERROR;
			}
		} else {/* Truncate file. */
			if (ftruncate64(fd,opt->FileSize)!=0) {
				printf("%s: Error: ftruncate64() failed. %s\n",opt->PathName,strerror(errno));
				result=0 /* false */;
				goto EXIT_CLOSE_ERROR;
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
						printf("%s: Error: ftruncate64() failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
						result=0 /* false */;
						goto EXIT_CLOSE_ERROR;
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
			if (!FillWriteFile(fd,img,img_size,opt)) {
				/* Fail to create. */
				result=0 /* false */;
				goto EXIT_CLOSE_ERROR;
			}
		}
	}
	if (fsync(fd)!=0) {
		printf("%s: Warning: fsync() failed. %s(%d)\n", opt->PathName, strerror(errno),errno);
	}
	if (close(fd)!=0) {
		printf("%s: Error: close() failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
		return 0;
	}
	printf("%s: Info: close. fd=%d, time=%" PRId64 "\n",opt->PathName, fd, (int64_t)(time(0)));
	printf("%s: Info: Sync.\n", opt->Argv0);
	sync();

	if (opt->FillFile!=0) {
		/* Need sleep to stabilize drive. */
		printf("%s: Info: Sleep. TestToTestSleeps=%u\n", opt->Argv0, opt->TestToTestSleeps);
		sleep(opt->TestToTestSleeps);
	}

	/* random read/write part. */
	fd_flags_add_random=0;
	if (opt->DoDirectRandomRW!=0) {
		fd_flags_add_random|=O_DIRECT;
	}

	flags=fd_flags_base | fd_flags_add_random;
	fd=open(opt->PathName
		,flags
		,S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
	);
	if (fd<0) {
		/* Can't open. */
		printf("%s: Error: open() failed. %s\n",opt->PathName,strerror(errno));
		return 0;
	}
	printf("%s: Info: open. fd=%d, flags=0x%x, time=%" PRId64 "\n",opt->PathName, fd, flags, (int64_t)(time(0)));

	if (!RandomRWFile(fd,img,img_size,img_locked,mem,mem_size,mem_locked,opt)) {
		/* Random read/write failed. */
		printf("%s: Error: random read/write failed. %s\n",opt->PathName,strerror(errno));
		result=0;
		goto EXIT_CLOSE_ERROR;
	}

	if (fsync(fd)!=0) {
		printf("%s: Warning: fsync() failed. %s(%d)\n", opt->PathName, strerror(errno),errno);
	}
	if (close(fd)!=0) {
		printf("%s: Error: close() failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
		return 0;
	}
	printf("%s: Info: close. fd=%d, time=%" PRId64 "\n",opt->PathName, fd, (int64_t)time(0));
	printf("%s: Info: Sync.\n", opt->Argv0);
	sync();

	if (opt->Repeats>0) {
		/* Need sleep to stabilize drive. */
		printf("%s: Info: Sleep. TestToTestSleeps=%u\n", opt->Argv0, opt->TestToTestSleeps);
		sleep(opt->TestToTestSleeps);
	}

	/* Sequential read() part. */
	flags=fd_flags_base | fd_flags_add_seq;
	fd=open(opt->PathName
		,flags
		,S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
	);

	if (fd<0) {
		/* Can't open. */
		printf("%s: Error: open() failed. %s\n",opt->PathName,strerror(errno));
		return 0;
	}
	printf("%s: Info: open. fd=%d, flags=0x%x, time=%" PRId64 "\n",opt->PathName, fd, flags, (int64_t)time(0));

	if (opt->DoReadFile!=0) {
		/* Do sequential read. */
		if (!ReadFile(fd,img,img_size,opt)) {
			printf("%s: Error: Sequential read failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
			result=0;
		}
	}
	if (fsync(fd)!=0) {
		printf("%s: Warning: fsync() failed. %s(%d)\n", opt->PathName, strerror(errno),errno);
	}
	if (close(fd)!=0) {
		printf("%s: Error: close() failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
		result=0;
	}
	printf("%s: Info: close. fd=%d, time=%" PRId64 "\n",opt->PathName, fd, (int64_t)time(0));
	printf("%s: Info: Sync.\n", opt->Argv0);
	sync();
	if (opt->DoReadFile!=0) {
		/* Need sleep to stabilize drive. */
		printf("%s: Info: Sleep. TestToTestSleeps=%u\n", opt->Argv0, opt->TestToTestSleeps);
		sleep(opt->TestToTestSleeps);
	}
	return(result);

EXIT_CLOSE_ERROR:;
	if (fsync(fd)!=0) {
		printf("%s: Warning: fsync() failed. %s(%d)\n", opt->PathName, strerror(errno),errno);
	}
	if (close(fd)!=0) {
		printf("%s: Error: close() failed. %s(%d)\n",opt->PathName,strerror(errno),errno);
		result=0;
	}
	printf("%s: Info: close. fd=%d, time=%" PRId64 "\n",opt->PathName, fd, (int64_t)time(0));
	printf("%s: Info: Sync.\n", opt->Argv0);
	sync();
	printf("%s: Info: Sleep. TestToTestSleeps=%u\n", opt->Argv0, opt->TestToTestSleeps);
	sleep(opt->TestToTestSleeps);
	return(result);
}

/*! Test main.
    @param opt command line option.
    @return int !=0: Pass, ==0: Failed.
*/
int MainB(TCommandLineOption *opt)
{	int		result;

	unsigned char	*mem;
	long		mem_size;
	char		mem_locked; /*!< Map random read memory with lock. */

	unsigned char	*img;
	long		img_size;
	char		img_locked; /*!< Map random write and sequential read/write memory with lock. */
	off64_t		img_blocks;

	result=1 /* true */;
	/* Initialize random seed. */
	init_genrand(opt->Seed);

	mem_locked=0;
	img_locked=0;
	/* allocate random read buffer mem. */
	mem_size=RoundUpBy((opt->BlockSize*opt->BlocksMax),ScPageSize);
	mem=mmap(NULL,mem_size
		,PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE | MAP_LOCKED
		,-1,0
	);

	if (mem==MAP_FAILED) {
		printf("%s(): Notice: Failed mmap() random read buffer with lock. %s(%d). mem_size=0x%lx\n"
			,__func__
			,strerror(errno), errno, mem_size
		);
		mem=mmap(NULL,mem_size
			,PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE
			,-1,0
		);
		if (mem==MAP_FAILED) {
			printf("%s(): Error: Failed mmap() random read buffer without lock. %s(%d). mem_size=0x%lx\n"
				,__func__
				,strerror(errno), errno, mem_size
			);
			return 0;
		} else {/* Map read memory without lock. */
			printf("%s(): Notice: mmap random read buffer without lock. %s(%d). mem_size=0x%lx\n"
				,__func__
				,strerror(errno), errno, mem_size
			);
		}
	} else {/* Map read memory with lock. */
		mem_locked=1;
	}

	/* allocate random write buffer img. */
	img_blocks=opt->BlocksMax*2;
	if (img_blocks<opt->SequentialRWBlocks) {
		/* random write buffer is less than sequential read/write buffer. */
		img_blocks=opt->SequentialRWBlocks;
	}
	img_size=RoundUpBy(opt->BlockSize*img_blocks, ScPageSize);
	img=mmap(NULL,img_size
		,PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE | MAP_LOCKED
		,-1,0);

	if (img==MAP_FAILED) {
		printf("%s(): Notice: Failed mmap() random write and sequential read/write buffer with lock. %s(%d). img_size=0x%lx\n"
			,__func__
			,strerror(errno), errno, img_size
		);
		img=mmap(NULL,img_size
			,PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE
			,-1,0
		);
		if (img==MAP_FAILED) {
			printf("%s(): Error: Failed random write and sequential read/write buffer without lock. %s(%d). img_size=0x%lx\n"
				,__func__
				,strerror(errno), errno, img_size
			);
			result=0 /* false */;
			goto EXIT_UNMAP_MEM;
		} else {/* Map write memory without lock. */
			printf("%s(): Notice: mmap() random write and sequential read/write buffer without lock. %s(%d). mem_size=0x%lx\n"
				,__func__
				,strerror(errno), errno, mem_size
			);
		}
	} else {/* Map write buffer memory with lock */
		img_locked=1;
	}
	FillRandomFileImage(img, img_size);
	if (opt->DoMark!=0) {
		PreMarkFileImage(img, img_size, opt->BlockSize);
	}

	/* Do read / write part. */
	if (!MainTestRW(img, img_size, img_locked, mem, mem_size, mem_locked, opt)) {
		/* Read / write test failed. */
		result=0;
	}

	if (img_locked) {
		/* Maped write buffer memory with lock. */
		if (munlock(img,img_size)!=0) {
			printf("%s(): Error: Failed munlock() random write and sequential read/write buffer %s(%d)\n",__func__,strerror(errno), errno);
			result=0;
		}
	}
	if (munmap(img,img_size)!=0) {
		printf("%s(): Error: Failed munmap() random write and sequential read/write buffer. %s(%d)\n",__func__,strerror(errno), errno);
		result=0;
	}

EXIT_UNMAP_MEM:;
	if (mem_locked) {
		/* Maped write buffer memory with lock. */
		if (munlock(mem,mem_size)!=0) {
			printf("%s(): Error: Failed munlock() random read buffer. %s(%d)\n",__func__,strerror(errno), errno);
			result=0;
		}
	}
	if (munmap(mem,mem_size)!=0) {
		printf("%s(): Error: Failed munmap() random read buffer. %s(%d)\n",__func__,strerror(errno),errno);
		result=0;
	}
	if (opt->DoMark==0) {
		/* Skip check, only touch memory. */
		printf("ReadMemorySum: Info: 0x%" PRIx64 "\n",ReadMemorySum);
	}
	return result;
}

void ShowHelp(void)
{	printf(copyright_notice);
	printf(
	"Command line: [-f n] [-p {y|n}] [-x {b|r|w}] [-r {y|n}] [-d {y|n}{Y|N}] [-m {y|n}] [-b n] [-u n] [-i n] [-a n] [-e n] [-n n] [-s n] path_name\n"
	"-f n work file size.\n"

	"-p{y|n} Fill file with initial image(y: fill, n: truncate)(%c).\n"
	"-x{b|r|w} Random read/write method (b: Do both read and write, r: Do read only, w: Do write only)(%s).\n"
	"-r{s|y|n} Read file from start block to end block (s: read strict check, y: read light check, n: do nothing)(%s).\n"

	"-d{y|n}{Y|N} Add O_DIRECT flag at sequential r/w (y: add, n: not add), at random r/w(Y: add, N: not add)(%c%c).\n"
	"-m{y|n} Do block number Marking and check (y: mark and check, n: do not marking)(%c).\n"

	"-b n block size(%d).\n"
	"-u n Sequential read/write blocks per one IO (if zero or not set, same as \"-a n\" * 2)(%d).\n"
	"-i n Random read/write minimum blocks(%d).\n"
	"-a n Random read/write maximum blocks(%d).\n"
	"-o n Start block number to read/write(%d).\n"
	"-e n End block number to read/write(%d).\n"
	"-n n number of random read/write access(%d).\n"
	"-s n random seed number(%d). \n"
	"-z n Sleep time in seconds after test(%u).\n"
	"path_name: File path name to test.\n"
	"Number n can be specified with unit {k|m|g|t}. k: x1024, m: x1024^2, g: x1024^3, t: x1024^4, p: x1024^5\n"
	,(DEF_FillFile ? 'y' : 'n')

	,do_only_options[DEF_DoRandomAccess]
	,do_read_file_options[DEF_DoReadFile]

	,(DEF_DoDirect ? 'y' : 'n')
	,(DEF_DoDirectRandomRW ? 'Y' : 'N')
	,(DEF_DoMark ? 'y' : 'n')

	,DEF_BlockSize
	,DEF_SequentialRWBlocks
	,DEF_BlocksMin
	,DEF_BlocksMax
	,0
	,0
	,DEF_Repeats

	,DEF_Seed
	,DEF_TestToTestSleeps
	);
	printf(
	"Output format: sequential write.\n"
	"cur b/s, total b/s, cur_el b/s, elp b/s, cur_pos, progs, Twrite, Twrite_total, Twrite_elapsed, Telapsed, Tmem_access_total\n"
	);
	printf(
	"Output format: random access.\n"
	"index, elapsed_time, rw, seek_position, length, "
	"access_time, bps, memory_access_time\n"
	);
	printf(
	"Output format: sequential read.\n"
	"cur b/s, total b/s, cur_el b/s, elp b/s, cur_pos, progs, Tread, Tread_total, Tread_elapsed, Telapsed, Tmem_access_total\n"
	);
}

int main(int argc, char **argv)
{
	/* Get Page Size. */
	ScPageSize=sysconf(_SC_PAGESIZE);
	if (ScPageSize<0) {
		printf("%s: Error: Failed sysconf(). %s(%d)\n", argv[0], strerror(errno), errno);
		return 1;
	}
	if (!TCommandLineOptionGetopt(&CommandLine,argc,argv)) {
		ShowHelp();
		return 1;
	}
	if (!MainB(&CommandLine)) {
		printf("%s: Fail: Test FAIL.\n",CommandLine.PathName);
		return 2;
	}
	printf("%s: Pass: Test PASS.\n",CommandLine.PathName);
	return(0);
}

