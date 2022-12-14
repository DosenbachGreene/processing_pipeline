#$Header: /home/usr/shimonyj/me_fmri/RCS/MEfmri_4dfp.mak,v 1.1 2021/07/24 04:30:26 avi Exp $
#$Log: MEfmri_4dfp.mak,v $
#Revision 1.1  2021/07/24 04:30:26  avi
#Initial revision
#

PROG	= MEfmri_4dfp
CSRCS	= ${PROG}.c hist.c
TRX	= ${NILSRC}/TRX
JSS	= ${NILSRC}/JSSutil
LOBJS   = ${JSS}/random.o ${JSS}/JSSnrutil.o ${JSS}/lin_algebra.o ${JSS}/JSSstatistics.o \
		  ${TRX}/endianio.o ${TRX}/Getifh.o ${TRX}/rec.o
OBJS    = ${CSRCS:.c=.o}

CFLAGS	= -fPIC -I${JSS} -I${TRX} -std=c11 -O
ifeq (${OSTYPE}, linux)
	CC	= gcc ${CFLAGS}
	LIBS	= -lm
else
	CC	= gcc ${CFLAGS}
	LIBS	= -lm
endif

.c.o:
	${CC} -c $<

${PROG}: ${OBJS} 
	${CC} -o $@ ${OBJS} ${LOBJS} ${LIBS}

clean:
	/bin/rm ${OBJS} ${PROG}

release: ${PROG}
	chmod 775 ${PROG}
	chgrp program ${PROG}
	/bin/mv ${PROG} ${RELEASE}
