/*$Header: /home/usr/shimonyj/me_fmri/RCS/MEfmri_4dfp.c,v 1.24 2023/07/10 09:58:12 avi Exp $*/
/*$Log: MEfmri_4dfp.c,v $
 *Revision 1.22  2023/05/04 10:04:50  avi
 *hist.h is needed here; hist.c and hist.o now found in JSSutil
 *
 *Revision 1.21  2023/05/04 09:14:42  avi
 *#include hist.h not needed here
 *
 *Revision 1.20  2022/12/14 19:37:40  avi
 *dimensions of sum[] and ssum[] increased from 4 to 9 to accommodate up to 9 TEs
 *
 *Revision 1.19  2021/07/24 03:54:41  avi
 *revise pointer arithmetic to accommodate giant-sized input data
 *
 *Revision 1.18  2021/05/04 10:07:35  avi
 *enable 64 bit imgtn addressing - requires inttypes.h and stdint.h
 *replace NaNs in output images with 1.e-37 (affect only Swgt)
 *
 *Revision 1.17  2021/03/28 09:15:08  avi
 *replace imgtn array with disk image of array reshaped as slices
 *
 * Revision 1.16  2021/03/27  09:01:55  avi
 * cosmetic code changes
 *
 * Revision 1.15  2021/03/11  11:40:23  avi
 * process command line option -e
 *
 * Revision 1.14  2021/03/10  02:11:38  avi
 * option -e (specify TE at which Sfit image is computed)
 * multiple cosmetic changes
 *
 * Revision 1.13  2021/03/09  07:47:33  avi
 * simplified 4dfp output code
 *
 * Revision 1.12  2021/03/09  05:47:34  avi
 * handle an arbitrary number of echos (previously 4 was hard coded)
 * minor stabilization of bad voxel handling
 *
 * Revision 1.10  2021/02/11 21:05:53  shimonyj
 * Revision 1.9  2015/10/24 23:57:41  avi
 * option -S (improved linear fitting)
 * output Sfit (pseudo single-echo BOLD)
 * better fit reporting
 *
 * Revision 1.7  2015/04/19  03:44:47  shimonyj
 * minor bug corrections
 *
 * Revision 1.6  2015/04/19  02:21:28  shimonyj
 * add test print out
 *
 * Revision 1.5  2015/04/17  23:40:46  shimonyj
 * Major revision of regularization
 *
 * Revision 1.4  2015/04/16  17:54:42  avi
 * correct option -T
 *
 * Revision 1.3  2015/04/16  17:29:36  shimonyj
 * minor edits
 *
 * Revision 1.2  2015/04/16  05:41:50  avi
 * options -T and -o
 **/

/*************************************/
/* MEfmri_4dfp                       */
/* process multi echo data 21Nov2014 */
/*************************************/
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <assert.h>
#include <string.h>
#include <JSSutil.h>
#include <JSSstatistics.h>
#include <Getifh.h>
#include <endianio.h>
#include <rec.h>

#include "hist.h"

#define MAXL 256 /* string length */

/*****************/
/* LM parameters */
/*****************/
#define PRT_FLG 0     /* extra print flag */
#define MAXP 2        /* maximum number of params to estimate */
#define NPOP 50       /* number of population members */
#define NITER 3       /* non linear number of iterations; original 2 */
#define DELCHI 0.1    /* min change in chisq; original 0.1 */
#define SSMOOTH 2     /* extent of spatial smoothing for pathological voxels */
#define BFRMFRAC 0.40 /* threshold for number of bad frames */
#define NSMOOTH 20    /* number of smoothing iterations for s0 regularization */
#define NVOL1 6       /* number of output volumes in imgQA QC1 4dfp */

/* output contents of img1: S0 */
/* output contents of img2: R2star */
/* output contents of img6: estimated S using tefit */
/* output contents of img3: sqrt(resid squared) */
/* output contents of imgQA */
/* volume 1 = original mask */
/* volume 2 = mask after removal of pathological pixels */
/* volume 3 = marks the pathological pixels */
/* volume 4 = marks the remaining path pixels after repair */
/* output contents of img5: weighted sum of S */

void mrqprior1(float x[], float y[], int ndata, float a[], int ia[], float aavg[], int ma, float **covar, float **alpha,
               float *logprob, float *alamda);
void mrqpcof(float x[], float y[], int ndata, float a[], int ia[], float aavg[], int ma, float **alpha, float beta[],
             float *logprob);
void r2sfunc(float x, float a[], float *y, float dyda[], int na);
int gaussj_chk(float **a, int n, float **b, int m);
void fitreg(float x[], float y[], int ndata, float sig[], int mwt, float a, float *b);
float mode(float s[], int ndata, float *std);

/*
** Generate fake R2* curves
** coefficients are:
**	a[1] = S0
**	a[2] = r2s
**
**	input te is the echo time
*/
float r2s_make(float te, float a[]) {
    /* return signal value */

    return (a[1] * exp(-te * a[2]));
}

/*
** Complete R2* model
** coefficients are:
**	a[1] = S0
**	a[2] = r2s
**
**	x is the te
*/
void r2sfunc(float x, float a[], float *y, float dyda[], int na) {
    *y = a[1] * exp(-x * a[2]);

    dyda[1] = exp(-x * a[2]);
    dyda[2] = -a[1] * x * exp(-x * a[2]);

    return;
}

/***********/
/* globals */
/***********/
static char rcsid[] = "$Id: MEfmri_4dfp.c,v 1.24 2023/07/10 09:58:12 avi Exp $";
static float TE[9];
/* Original Kundu values	12   28   44  60 */
/* WashU MEDEX values		15   28,  42, 55 */
/* UCSD MEDEX values		14.8 28.4 42  55.6 */
static int debug_flag = 0;

float ***calloc_float3(int n1, int n2, int n3) {
    unsigned int i, j;
    float ***a;

    if (!(a = (float ***)malloc(n1 * sizeof(float **)))) errm("calloc_float3");
    if (!(a[0] = (float **)malloc(n1 * n2 * sizeof(float *)))) errm("calloc_float3");
    if (!(a[0][0] = (float *)calloc((uint64_t)n1 * n2 * n3, sizeof(float)))) errm("calloc_float3");
    for (i = 0; i < n1; i++) {
        a[i] = a[0] + n2 * i;
        for (j = 0; j < n2; j++) {
            a[i][j] = a[0][0] + (uint64_t)n3 * (n2 * i + j);
        }
    }
    return a;
}

void free_float3(float ***a) {
    free(a[0][0]);
    free(a[0]);
    free(a);
}

static int split(char *string, char *srgv[], int maxp) {
    int i, m;
    char *ptr;

    if (ptr = strchr(string, '#')) *ptr = '\0';
    i = m = 0;
    while (m < maxp) {
        while (!isgraph((int)string[i]) && string[i]) i++;
        if (!string[i]) break;
        srgv[m++] = string + i;
        while (isgraph((int)string[i])) i++;
        if (!string[i]) break;
        string[i++] = '\0';
    }
    return m;
}

static void MEfmri_out(char *outroot, float *imag, int size, IFH ifh, char control, int nframe, char *imgroot, int argc,
                       char **argv, char *program) {
    FILE *fp;
    char imgfile[MAXL], outfile[MAXL], command[2 * MAXL];
    int i, status = 0;

    /***************************/
    /* replace NaN with 1.e-37 */
    /***************************/
    for (i = 0; i < size; i++)
        if (isnan(imag[i])) imag[i] = (float)1.e-37;
    sprintf(outfile, "%s.4dfp.img", outroot);
    if (!(fp = fopen(outfile, "wb")) || ewrite(imag, size, control, fp) || fclose(fp)) errw(program, outfile);
    /*******/
    /* ifh */
    /*******/
    ifh.matrix_size[3] = nframe;
    writeifhmce(program, outfile, ifh.matrix_size, ifh.scaling_factor, ifh.orientation, ifh.mmppix, ifh.center,
                control);
    /*******/
    /* hdr */
    /*******/
    sprintf(command, "ifh2hdr %s", outroot);
    printf("%s\n", command);
    status |= system(command);
    if (status) {
        fprintf(stderr, "%s: %s ifh2hdr error\n", program, imgroot);
        exit(status);
    }
    /*******/
    /* rec */
    /*******/
    sprintf(imgfile, "%s.4dfp.img", imgroot);
    startrece(outfile, argc, argv, rcsid, control);
    catrec(imgfile);
    endrec();
}

void write_command_line(char *program, FILE *outfp, int argc, char *argv[]) {
    int i;
    fprintf(outfp, "#%s", program);
    for (i = 1; i < argc; i++) fprintf(outfp, " %s", argv[i]);
    fprintf(outfp, "\n");
    fprintf(outfp, "#%s\n", rcsid);
}

void usage(char *program) {
    printf("Usage:	%s -E<int> -T <flt> <flt> ... <4dfp echo1> <4dfp echo2> ...\n", program);
    printf(" e.g., %s -E4 -T 15 28.25 41.5 54.75 WU20001_1_run1_echo[1234]_xr3d_atl.4dfp.img -r1 -otest -e30\n",
           program);
    printf("	option\n");
    printf("	-h	list output volume parameters\n");
    printf("	-N	use nonlinear estimation, longer processing time \n");
    printf("	-o<str>	specify output fileroot (default is first named image)\n");
    printf("	-s<int>	compute only selected slice (counting from 0)\n");
    printf("	-f<int>	select number of input frames (counting from 0)\n");
    printf("	-t<flt>	set threshold \n");
    printf("	-r<int>	regularize on the value of S0, 1:mean, 2:smooth curve\n");
    printf("	-E<int>	specify number of echos\n");
    printf("	-e<flt>	specify TE at which to model Sfit (default second second TE)\n");
    printf("	-T <flt> <flt> ... set TE values in msec\n");
    printf("	-a<int>\tperform local averaging on input,  1 2d3x3, 2 2d5x5, 3 3d3x3, 4 3d5x5\n");
    printf("	-@<b|l>\toutput big or little endian (default input endian)\n");
    printf("Output:\n");
    printf("\tfiles vol dim x nframes, S0, R2*, Res, Sfit, Swgt\n");
    printf("\tfile QC1 various masks \n");
    exit(1);
}

/**************/
/* start main */
/**************/
int main(int argc, char **argv) {
    float r2s_make(float t, float a[]);

    float pixelr2s(int nparam, int ndata, float *x, float *y, float *aopt, float *aostd, int *lista, float *aavg,
                   float *asig, float *amin, float *amax, float **covar, float **alpha);

    int NTE = 0; /* number of TEs must be set on input */
    int *lista, npix, npix0, npix1, npix2, nparam;
    float *x, *y, **covar, **alpha, logp, *sig, *lny, *y2, *xb, tefit = 0.;
    float *avgte, *stdte, *avgs0, *stds0;
    float avgt, stdt, ss0, s2s0, sr2, s2r2, sx, sxx, sxy;
    float aopt1[MAXP + 1], amin[MAXP + 1], amax[MAXP + 1], aavg[MAXP + 1], asig[MAXP + 1];
    float aopt[MAXP + 1], aostd[MAXP + 1], dyda[MAXP + 1], aoptrr[MAXP + 1];
    float avggray, tscmin;
    float sumr2, sumr2i, sumri, ssum2;
    float resmode, resstd;
    float thresh = 100.0; /* default from first echo */

    /***************/
    /* 4dfp images */
    /***************/
    FILE *fp, *imgsnfp;
    IFH ifh;
    char imgroot[9][MAXL], outroot[MAXL] = "", outroot1[MAXL];
    char outfile[MAXL], imgfile[MAXL], tmpfile[MAXL] = "temp.4dfp.img";
    float voxdim[3];
    int imgdim[4], sdim, vdim, nframe, tedim, orient, isbig, isbig1;
    char control = '\0';

    /*******************/
    /* modeling images */
    /*******************/
    float ***imgsn, *imgtn, *img1, *img2, *img6, *img3, *imgQA, *img5;
    char *mask, *mask1, *badpix;
    float *r2s, *s0, *s0new, *res, *res1;
    float *imgS0, *imgR2, *imgwn;

    /***********/
    /* utility */
    /***********/
    char *str, program[MAXL], command[MAXL], *srgv[MAXL];
    int c, xc, nx, ii, il, i1, j1, k1, i2, j2, k2;
    unsigned int i, j, k, l, m, jndex, jndex1, ndata, navg;
    float sum[9], ssum[9], tsum, temp;
    char *parnames[MAXP] = {"S0", "R2*"};
    char *vollabels1[NVOL1] = {"orig mask", "mask minus bad pix", "bad pixels", "bad pix after cleanup", "N", "N"};
    float a, b, siga, sigb, chi2, q, lcc;
    uint64_t kndex;

    /*********/
    /* flags */
    /*********/
    int status = 0;
    int slc_flag = 0, slcsel;
    int frame_flag = 0, nframein;
    int nonlin_flag = 0;
    int iavg_flag = 0;
    int regular_flag = 0;
    int median_flag = 0, medsize = 9;
    int iavg_slice = 1;

    printf("%s\n", rcsid);
    if (!(str = strrchr(argv[0], '/')))
        str = argv[0];
    else
        str++;
    strcpy(program, str);
    /************************/
    /* process command line */
    /************************/
    for (k = 0, i = 1; i < argc; i++) {
        if (*argv[i] == '-') {
            strcpy(command, argv[i]);
            str = command;
            while (c = *str++) switch (c) {
                    case 'N':
                        nonlin_flag++;
                        break;
                    case 'E':
                        NTE = atoi(str);
                        *str = '\0';
                        break;
                    case '@':
                        control = *str++;
                        *str = '\0';
                        break;
                    case 'e':
                        tefit = 0.001 * atof(str);
                        *str = '\0';
                        break;
                    case 'a':
                        iavg_flag++;
                        iavg_slice = atoi(str);
                        *str = '\0';
                        break;
                    case 'r':
                        regular_flag = atoi(str);
                        *str = '\0';
                        break;
                    case 's':
                        slc_flag++;
                        slcsel = atoi(str);
                        *str = '\0';
                        break;
                    case 'f':
                        frame_flag++;
                        nframein = atoi(str);
                        *str = '\0';
                        break;
                    case 't':
                        thresh = atof(str);
                        *str = '\0';
                        break;
                    case 'o':
                        getroot(str, outroot);
                        *str = '\0';
                        break;
                    case 'T':
                        if (!NTE) {
                            printf("%s: number of echos (-E<int>) must be defined first\n", program);
                            usage(program);
                        }
                        for (j = 0; j < NTE; j++) {
                            TE[j] = 0.001 * atof(argv[++i]);
                            if (TE[j] <= 0.) {
                                printf("%s: illegal TE values\n", program);
                                usage(program);
                            }
                        }
                        *str = '\0';
                        break;
                    case 'h':
                        for (j = 0; j < NVOL1; j++) {
                            printf("QC1 file %-5d %s\n", j + 1, vollabels1[j]);
                        }
                        exit(0);
                        break;
                }
        } else
            switch (k) {
                case 0:
                    for (j = 0; j < NTE; j++) {
                        getroot(argv[i + j], imgroot[j]);
                        k++;
                    }
                    break;
            }
    }
    if (NTE < 2 || NTE > 9) {
        printf("%s: NTE must be between 2 and 9\n", program);
        usage(program);
    }
    if (!strlen(outroot)) strcpy(outroot, imgroot[0]);

    /*************************************/
    /* QC different file and flag inputs */
    /*************************************/
    printf("input files:");
    for (j = 0; j < NTE; j++) printf(" %s", imgroot[j]);
    printf("\n");
    printf("option settings: slc_flag=%d slice=%d Nonlinear flag=%d\n", slc_flag, slcsel, nonlin_flag);
    printf("TE values (in msec):");
    for (j = 0; j < NTE; j++) printf(" %.1f", 1000. * TE[j]);
    printf("\n");

    /******************************************************/
    /* get stack dimensions for the different input files */
    /******************************************************/
    if (Getifh(imgroot[0], &ifh)) errr(program, imgroot[0]);
    isbig = strcmp(ifh.imagedata_byte_order, "littleendian");
    printf("isbig=%d\n", isbig);
    if (!control) control = (isbig) ? 'b' : 'l';
    for (k = 0; k < 4; k++) imgdim[k] = ifh.matrix_size[k];
    printf("stack dimensions: %d %d %d %d\n", imgdim[0], imgdim[1], imgdim[2], imgdim[3]);
    for (j = 1; j < NTE; j++) {
        if (Getifh(imgroot[j], &ifh)) errr(program, imgroot[j]);
        isbig1 = strcmp(ifh.imagedata_byte_order, "littleendian");
        printf("isbig=%d\n", isbig1);
        for (k = 0; k < 4; k++) status |= (imgdim[k] != ifh.matrix_size[k]);
        status |= (isbig1 != isbig);
    }
    if (status) {
        printf("%s error: mismatched input images\n", program);
        exit(-1);
    }

    /***************************************/
    /* allocate input memory and get stack */
    /***************************************/
    sdim = imgdim[0] * imgdim[1];
    vdim = imgdim[0] * imgdim[1] * imgdim[2];
    if (frame_flag == 0) {
        nframe = imgdim[3];
        tedim = vdim * imgdim[3];
    } else {
        nframe = nframein;
        tedim = vdim * nframein;
    }

    /* allocate input data array */
    printf("input data size in bytes = %ld\n", (uint64_t)NTE * tedim);
    if (!(imgtn = (float *)calloc((uint64_t)NTE * tedim, sizeof(float)))) errm(program);
    /* read input data */
    for (j = 0; j < NTE; j++) {
        sprintf(imgfile, "%s.4dfp.img", imgroot[j]);
        printf("Reading: echo %d %s\n", j + 1, imgfile);
        if (!(fp = fopen(imgfile, "rb")) || eread(&imgtn[(uint64_t)j * tedim], tedim, isbig, fp) || fclose(fp))
            errr(program, imgfile);
    }
    /*********************************************************/
    /* create disk image of imgsn = imgtn reshaped as slices */
    /*********************************************************/
    imgsn = calloc_float3(sdim, nframe, NTE); /* one slice of ME data */
    if (!(imgsnfp = fopen(tmpfile, "w+b"))) errw(program, tmpfile);
    for (k = 0; k < imgdim[2]; k++) {
        for (i = 0; i < sdim; i++)
            for (l = 0; l < nframe; l++)
                for (m = 0; m < NTE; m++) {
                    jndex = k * sdim + i;
                    kndex = (uint64_t)m * tedim + l * vdim + jndex;
                    /*			imgsn[i][l][m] = (imgtn + m*tedim + l*vdim)[jndex];	*/
                    imgsn[i][l][m] = imgtn[kndex];
                }
        if (fwrite(&imgsn[0][0][0], sizeof(float), sdim * nframe * NTE, imgsnfp) < sdim * nframe * NTE)
            errw(program, tmpfile);
    }
    rewind(imgsnfp);
    if (0) {
        for (k = 0; k < imgdim[2]; k++) {
            if (fseek(imgsnfp, (long)k * sdim * nframe * NTE * sizeof(float), SEEK_SET) ||
                fread(&imgsn[0][0][0], sizeof(float), sdim * nframe * NTE, imgsnfp) < sdim * nframe * NTE)
                errr(program, tmpfile);
            for (i = 0; i < sdim; i++)
                for (l = 0; l < nframe; l++)
                    for (m = 0; m < NTE; m++) {
                        jndex = k * sdim + i;
                        kndex = (uint64_t)m * tedim + l * vdim + jndex;
                        assert(imgsn[i][l][m] == imgtn[kndex]);
                    }
        }
        rewind(imgsnfp);
    }
    free(imgtn);

    /* allocate main output data arrays */
    if (!(img1 = (float *)calloc(tedim, sizeof(float)))) errm(program);
    if (!(img2 = (float *)calloc(tedim, sizeof(float)))) errm(program);
    if (!(img6 = (float *)calloc(tedim, sizeof(float)))) errm(program);
    if (!(img3 = (float *)calloc(tedim, sizeof(float)))) errm(program);
    if (!(img5 = (float *)calloc(tedim, sizeof(float)))) errm(program);

    if (!(imgS0 = (float *)calloc(vdim, sizeof(float)))) errm(program);
    if (!(imgR2 = (float *)calloc(vdim, sizeof(float)))) errm(program);

    if (!(imgQA = (float *)calloc(NVOL1 * vdim, sizeof(float)))) errm(program);
    if (!(imgwn = (float *)calloc(NTE * vdim, sizeof(float)))) errm(program);

    /* allocate mask arrays */
    if (!(mask = (char *)calloc(vdim, sizeof(char)))) errm(program);
    if (!(mask1 = (char *)calloc(vdim, sizeof(char)))) errm(program);
    if (!(badpix = (char *)calloc(nframe, sizeof(char)))) errm(program);
    if (!(r2s = (float *)calloc(nframe, sizeof(float)))) errm(program);
    if (!(s0 = (float *)calloc(nframe, sizeof(float)))) errm(program);
    if (!(s0new = (float *)calloc(nframe, sizeof(float)))) errm(program);
    if (!(res = (float *)calloc(nframe, sizeof(float)))) errm(program);
    if (!(res1 = (float *)calloc(nframe, sizeof(float)))) errm(program);

    /**************************/
    /* allocate for LM method */
    /**************************/
    lista = ivector(1, MAXP);
    x = vector(1, NTE);
    y = vector(1, NTE);
    y2 = vector(1, NTE);
    covar = matrix(1, MAXP, 1, MAXP);
    alpha = matrix(1, MAXP, 1, MAXP);
    sig = vector(1, NTE);
    lny = vector(1, NTE);
    avgte = vector(1, NTE);
    stdte = vector(1, NTE);
    avgs0 = vector(1, NTE);
    stds0 = vector(1, NTE);
    xb = vector(1, NTE);

    /**************************************/
    /* calculate weighted signal and mask */
    /**************************************/
    sx = sxx = 0.0;
    for (k = 1; k <= NTE; k++) {
        x[k] = TE[k - 1];
        sx += x[k];
        sxx += x[k] * x[k];
        sum[k - 1] = 0.0;
        ssum[k - 1] = 0.0;
    }
    if (tefit == 0.0) tefit = x[2]; /* TE at which to model Sfit */

    printf("processing weighted signal slice");
    npix = 0;
    for (k = 0; k < imgdim[2]; k++) {
        printf(" %d", k + 1);
        fflush(stdout);
        if (fseek(imgsnfp, (long)k * sdim * nframe * NTE * sizeof(float), SEEK_SET) ||
            fread(&imgsn[0][0][0], sizeof(float), sdim * nframe * NTE, imgsnfp) < sdim * nframe * NTE)
            errr(program, tmpfile);
        for (m = 0; m < sdim; m++) {
            i = k * sdim + m;
            for (ii = 1; ii <= NTE; ii++) {
                y[ii] = 0.0;
                for (l = 0; l < nframe; l++) {
                    /*	assert (imgsn[m][l][ii-1] == (imgtn + (ii-1)*tedim + l*vdim)[i]);
                            y[ii] += (imgtn + (ii-1)*tedim + l*vdim)[i];	*/
                    y[ii] += imgsn[m][l][ii - 1];
                }
                y[ii] /= nframe;
            }
            if (0) {
                printf("voxel_index=%d y[]=", i);
                for (ii = 1; ii <= NTE; ii++) printf(" %.1f", y[ii]);
                printf("\n");
            }
            /* create mask using first echo average */
            /* NOTE: usage between mask and mask1 is opposite */
            /* mask ==1 indicates good pixel to process, ==0 indicates background */
            /* mask1 ==1 indicates a problem with a pixel */
            if (y[1] < thresh) {
                mask[i] = 0;
                mask1[i] = 0;
            } else {
                npix++;
                mask[i] = 1;
                mask1[i] = 0;
                imgQA[i + 0 * vdim] = 1; /* store mask for ouput */
                imgQA[i + 1 * vdim] = 1; /* store mask for ouput */

                /* set up linear estimation y = a + bx */
                for (j = 1; j <= NTE; j++) {
                    if (y[j] <= 0.0) y[j] = 1.0; /* fake number */
                    lny[j] = log(y[j]);
                    sig[j] = 1.0 / lny[j];
                    sum[j - 1] += y[j];
                    ssum[j - 1] += y[j] * y[j];
                }

                fit(x, lny, NTE, sig, 1, &a, &b, &siga, &sigb, &chi2, &q, &lcc);
                imgS0[i] = exp(a);
                imgR2[i] = -b;
                for (ii = 1; ii <= NTE; ii++) {
                    imgwn[i + (ii - 1) * vdim] = x[ii] * exp(x[ii] * b);
                }

                /* calc weighted signal for output */
                for (l = 0; l < nframe; l++) {
                    img5[i + l * vdim] = 0;
                    tsum = 0;
                    for (ii = 1; ii <= NTE; ii++) {
                        /*	assert (imgsn[m][l][ii-1] ==               (imgtn + (ii-1)*tedim + l*vdim)[i]);
                                img5[i + l*vdim] += imgwn[i + (ii-1)*vdim]*(imgtn + (ii-1)*tedim + l*vdim)[i];	*/
                        img5[i + l * vdim] += imgwn[i + (ii - 1) * vdim] * imgsn[m][l][ii - 1];
                        tsum += imgwn[i + (ii - 1) * vdim];
                    }
                    img5[i + l * vdim] /= tsum;
                }
            }
        }
    } /* end i loop on voxels */

    /* sum over both space and time */
    for (k = 1; k <= NTE; k++) {
        avgs0[k] = sum[k - 1] / npix;
        stds0[k] = sqrt((npix * ssum[k - 1] - sum[k - 1] * sum[k - 1]) / (npix * (npix - 1)));
    }

    /***********************/
    /* print values for QC */
    /***********************/
    printf("\nTEST SECTION FOR LINEAR AND NONLIN REGRESSION CALCS\n");
    printf("y values are global sums over both space and time\n");
    for (i = 1; i <= NTE; i++) {
        y[i] = sum[i - 1] / npix;
        printf("TE %d x = %f y = %f npix = %d\n", i, x[i], y[i], npix);
    }

    /*******************************************************/
    /* test linear and nonlinear estimation on global data */
    /*******************************************************/
    /* set up linear estimation y = a + bx */
    for (i = 1; i <= NTE; i++) {
        lny[i] = log(y[i]);
        sig[i] = 1.0 / lny[i];
    }

    fit(x, lny, NTE, sig, 1, &a, &b, &siga, &sigb, &chi2, &q, &lcc);

    printf("linear logS0  = %f (%f)\n", a, siga);
    printf("linear S0  = %f (%f)\n", exp(a), exp(siga));
    printf("linear R2* = %f (%f)\n", b, sigb);

    /* calculate the linear residual error */
    /* NOTE: Results from the linear analysis is log(S0) and -R2* */
    sumr2 = 0.0;
    aopt[1] = exp(a);
    aopt[2] = -b;
    for (i = 1; i <= NTE; i++) {
        sumr2i = (y[i] - r2s_make(x[i], aopt));
        sumr2 += sumr2i * sumr2i;
        sumri = lny[i] - (a + b * x[i]);
        printf("%d y=%f model=%f lin res=%f\n", i, y[i], r2s_make(x[i], aopt), sumr2i);
    }
    sumr2 /= NTE;
    printf("sqrt(sum(res^2)/N) = %f\n", sqrt(sumr2));
    if (1) {
        /* set up model nonlinear */
        /* NOTE: Non-linear expects S0 and positive R2* */
        /* 1: s0, 2: r2s */

        /* init S0 */
        aavg[1] = exp(a);
        amin[1] = 0.2 * aavg[1];
        amax[1] = 2.0 * aavg[1];

        /* init r2s in units of 1/sec */
        aavg[2] = -b;
        amin[2] = 0.2 * aavg[2];
        amax[2] = 2.0 * aavg[2];

        /* init lista */
        nparam = 2;
        for (i = 1; i <= nparam; i++) {
            lista[i] = 2;
            asig[i] = (amax[i] - amin[i]) / 4.0;
        }

        /* do nonlinear analysis */
        logp = pixelr2s(nparam, NTE, x, y, aopt, aostd, lista, aavg, asig, amin, amax, covar, alpha);

        for (i = 1; i <= nparam; i++) {
            printf("nonlin param %d = %f (%f)\n", i, aopt[i], aostd[i]);
        }
        printf("nonlin logprob = %f\n", logp);

        /* calculate the nonlinear residual error */
        sumr2 = 0.0;
        for (i = 1; i <= NTE; i++) {
            sumr2i = (y[i] - r2s_make(x[i], aopt));
            sumr2 += sumr2i * sumr2i;
            printf("%d y=%f model=%f nlin res=%f\n", i, y[i], r2s_make(x[i], aopt), sumr2i);
        }
        sumr2 /= NTE;
        printf("sqrt(sum(res^2)/N) = %f\n", sqrt(sumr2));
        printf("\n---------------------------------------------\n");
    }

    /***********************************/
    /* loop over voxels to be analyzed */
    /***********************************/
    rewind(imgsnfp);
    printf("processing slice");
    npix = 0;
    for (k = 0; k < imgdim[2]; k++) { /* slice counter */
        printf(" %d", k + 1);
        fflush(stdout);
        if (slc_flag && (slcsel != k)) continue; /* single slice case */
        if (fseek(imgsnfp, (long)k * sdim * nframe * NTE * sizeof(float), SEEK_SET) ||
            fread(&imgsn[0][0][0], sizeof(float), sdim * nframe * NTE, imgsnfp) < sdim * nframe * NTE)
            errr(program, tmpfile);

        for (j = 0; j < sdim; j++) { /* loop pixel within each slice */
            jndex = k * sdim + j;

            if (mask[jndex]) { /* mask voxels */
                npix++;

                /********************************************************/
                /* LOOP 1 average the time domain to get error estimate */
                /********************************************************/
                for (i = 1; i <= NTE; i++) {
                    y[i] = 0.0;
                    y2[i] = 0.0;
                }
                for (l = 0; l < nframe; l++) {
                    for (ii = 1; ii <= NTE; ii++) {
                        /*	  assert (imgsn[j][l][ii-1] == (imgtn + (ii-1)*tedim + l*vdim)[jndex]);
                                                        temp = (imgtn + (ii-1)*tedim + l*vdim)[jndex];	*/
                        temp = imgsn[j][l][ii - 1];
                        y[ii] += temp;
                        y2[ii] += temp * temp;
                    }
                } /* end 1st frame loop */

                /* get standard deviation */
                for (i = 1; i <= NTE; i++) {
                    y[i] /= nframe;
                    avgte[i] = y[i];
                    stdte[i] = sqrt((y2[i] - nframe * y[i] * y[i]) / (nframe - 1));
                }

                /*********************************************************/
                /* LOOP 2 linear calc each frame and prep regularization */
                /*********************************************************/
                npix0 = 0;
                for (l = 0; l < nframe; l++) {
                    for (ii = 1; ii <= NTE; ii++) {
                        /*	y[ii] = (imgtn + (ii-1)*tedim + l*vdim)[jndex];`*/
                        y[ii] = imgsn[j][l][ii - 1];
                    }

                    /* count number of negative values */
                    badpix[l] = 0;
                    xc = 0;
                    for (i = 1; i <= NTE; i++) {
                        if (y[i] <= 0.0) xc++;
                    }

                    /* all data positive do linear estimate */
                    /* OPTION: use stdte for sig from above calculation */
                    if (xc == 0) {
                        for (i = 1; i <= NTE; i++) {
                            lny[i] = log(y[i]);
                            sig[i] = 1.0 / lny[i];
                        }
                        fit(x, lny, NTE, sig, 1, &a, &b, &siga, &sigb, &chi2, &q, &lcc);

                        aopt[1] = exp(a);
                        aopt[2] = -b;
                    }
                    /* failure: 3 neg values or first value y[1]<0  */
                    else if (y[1] <= 0.0 || xc > 2) {
                        /* printf("zero %f %f %f %f\n",y[1],y[2],y[3],y[4]); */
                        aopt[1] = 0.0;
                        aopt[2] = 0.0;
                    }
                    /* If 3 or more good points remove bad points and estimate */
                    else if (NTE - xc >= 3) {
                        i1 = 0;
                        for (i = 1; i <= NTE; i++) {
                            if (y[i] > 0.0) {
                                i1++;
                                xb[i1] = x[i];
                                lny[i1] = log(y[i]);
                                sig[i1] = 1.0 / lny[i];
                            }
                        }
                        fit(xb, lny, i1, sig, 1, &a, &b, &siga, &sigb, &chi2, &q, &lcc);

                        aopt[1] = exp(a);
                        aopt[2] = -b;
                    }
                    /* if only 2 points estimate from straight line */
                    else if (NTE - xc == 2) {
                        for (i = 1; i <= NTE; i++) {
                            if (y[i] > 0.0) nx = i;
                        }
                        b = (log(y[nx]) - log(y[1])) / (x[nx] - x[1]);
                        a = log(y[1]) - b * x[1];
                        aopt[1] = exp(a);
                        aopt[2] = -b;
                    }

                    /* mark bad values */
                    if (aopt[1] <= 0.0 || aopt[2] <= 0.0 || !isfinite(aopt[1]) || !isfinite(aopt[2])) {
                        /* printf("neg slope %f %f %f %f\n",y[1],y[2],y[3],y[4]); */
                        badpix[l] = 1;
                        s0[l] = 0.0;
                        r2s[l] = 0.0;
                    } else { /* store good fits for regularization */
                        npix0++;
                        badpix[l] = 0;
                        s0[l] = aopt[1];
                        r2s[l] = aopt[2];

                        /* calc the residual error */
                        sumr2 = 0.0;
                        for (i = 1; i <= NTE; i++) {
                            sumr2 += (y[i] - r2s_make(x[i], aopt)) * (y[i] - r2s_make(x[i], aopt));
                        }
                        res[l] = sqrt(sumr2 / NTE);
                        res1[npix0 - 1] = sqrt(sumr2 / NTE);
                    }
                } /* end of 2nd "l" loop on frames */

                /* check for really bad pixels = lots of bad values */
                if (npix0 < BFRMFRAC * nframe) {
                    mask1[jndex] = 1;
                    imgQA[jndex + 2 * vdim] = 1;
                    imgQA[jndex + 3 * vdim] = 1;
                    continue;
                } else { /* get mod and std on res for decent pixels */
                    resmode = mode(res1, npix0, &resstd);

                    /* recalculate S0 avg using the mode values */
                    npix2 = 0;
                    ss0 = 0.0;
                    s2s0 = 0.0;
                    sr2 = 0.0;
                    s2r2 = 0.0;
                    for (l = 0; l < nframe; l++) {
                        if (badpix[l] == 1) continue;
                        if (res[l] > resmode + 2 * resstd) continue;
                        npix2++;
                        ss0 += s0[l];
                        s2s0 += s0[l] * s0[l];
                        sr2 += r2s[l];
                        s2r2 += r2s[l] * r2s[l];
                    }
                }

                /******************************/
                /* LOOP 3 Fill in gaps in S0  */
                /* Also fill in R2S as backup */
                /******************************/
                /* front edge gap */
                if (badpix[0] != 0 && badpix[1] == 0) {
                    s0[0] = s0[1];
                    r2s[0] = r2s[1];
                } else if (badpix[0] != 0 && badpix[1] != 0 && badpix[2] == 0) {
                    s0[0] = s0[2];
                    s0[1] = s0[2];
                    r2s[0] = r2s[2];
                    r2s[1] = r2s[2];
                }

                /* back end gap */
                if (badpix[nframe - 1] != 0 && badpix[nframe - 2] == 0) {
                    s0[nframe - 1] = s0[nframe - 2];
                    r2s[nframe - 1] = r2s[nframe - 2];
                } else if (badpix[nframe - 1] != 0 && badpix[nframe - 2] != 0 && badpix[nframe - 3] == 0) {
                    s0[nframe - 1] = s0[nframe - 3];
                    s0[nframe - 2] = s0[nframe - 3];
                    r2s[nframe - 1] = r2s[nframe - 3];
                    r2s[nframe - 2] = r2s[nframe - 3];
                }

                for (l = 0; l < nframe; l++) {
                    if (badpix[l] == 0) continue;

                    /* replace with avg value */
                    if (s0[l] <= 0.0) s0[l] = ss0 / npix2;   /* fill s0 with best avg. */
                    if (r2s[l] <= 0.0) r2s[l] = sr2 / npix2; /* backup fill, not ideal */

                    /* replace with nearest neighbor when possible */
                    if (l >= 1 && l <= nframe - 2) {
                        if (badpix[l - 1] == 0 && badpix[l + 1] == 0) {
                            s0[l] = 0.5 * (s0[l - 1] + s0[l + 1]);
                            r2s[l] = 0.5 * (r2s[l - 1] + r2s[l + 1]);
                        }
                    }

                    /* next nearest neighbor case */
                    if (l >= 1 && l <= nframe - 3) {
                        if (badpix[l - 1] == 0 && badpix[l + 1] != 0 && badpix[l + 2] == 0) {
                            s0[l] = 0.5 * (s0[l - 1] + s0[l + 2]);
                            s0[l + 1] = 0.5 * (s0[l - 1] + s0[l + 2]);
                            r2s[l] = 0.5 * (r2s[l - 1] + r2s[l + 2]);
                            r2s[l + 1] = 0.5 * (r2s[l - 1] + r2s[l + 2]);
                        }
                    }

                } /* end of 3rd frame loop */

                /* s0 should NOT be zero at this point */
                xc = 0;
                for (l = 0; l < nframe; l++) {
                    if (s0[l] == 0) xc++;
                }
                if (xc != 0) {
                    printf("\n Error(main): After loop 3, pix %d s0 has %d zeros\n", jndex, xc);
                    for (l = 0; l < nframe; l++) {
                        printf("%d s0 %f r2s %f bad %d\n", l, s0[l], r2s[l], badpix[l]);
                    }
                    mask1[jndex] = 1;
                    imgQA[jndex + 2*vdim] = 1;
                    imgQA[jndex + 3*vdim] = 1;
                    continue;
                }

                /* Smooth s0 if regular_flag == 2 */
                if (regular_flag == 2) {
                    for (i = 0; i < NSMOOTH; i++) {
                        for (l = 1; l < nframe - 1; l++) s0new[l] = 0.25 * (s0[l - 1] + 2 * s0[l] + s0[l + 1]);
                        for (l = 1; l < nframe - 1; l++) s0[l] = s0new[l];
                    }
                }

                /********************************************************/
                /* LOOP 4 Loop on frames and perform final calculations */
                /********************************************************/
                for (l = 0; l < nframe; l++) {
                    for (ii = 1; ii <= NTE; ii++) {
                        /*	y[ii] = (imgtn + (ii-1)*tedim + l*vdim)[jndex];	*/
                        y[ii] = imgsn[j][l][ii - 1];
                    }

                    /* linear no global regularization */
                    /* will still regularize for bad fits */
                    if (nonlin_flag == 0 && regular_flag == 0) {
                        /* bad pixel option so regularize */
                        if (badpix[l]) {
                            aopt[1] = s0[l];
                            sxy = 0.0;
                            xc = 0;
                            for (i = 1; i <= NTE; i++) {
                                if (y[i] > 0.0) {
                                    xc++;
                                    lny[i] = log(y[i]);
                                    sxy = sxy + x[i] * lny[i];
                                }
                            }
                            if (xc >= 2)
                                aopt[2] = -(sxy - log(aopt[1]) * sx) / sxx;
                            else
                                aopt[2] = r2s[l];
                        }
                        /* good pix option use results as is */
                        else {
                            aopt[1] = s0[l];
                            aopt[2] = r2s[l];
                        }
                    }

                    /* nonlinear no global regularization */
                    /* will regularize for bad fits */
                    else if (nonlin_flag && regular_flag == 0) {
                        if (badpix[l]) { /* bad pixel option */

                            aopt[1] = s0[l];
                            sxy = 0.0;
                            xc = 0;
                            for (i = 1; i <= NTE; i++) {
                                if (y[i] > 0.0) {
                                    xc++;
                                    lny[i] = log(y[i]);
                                    sxy = sxy + x[i] * lny[i];
                                }
                            }
                            if (xc >= 2)
                                aopt[2] = -(sxy - log(aopt[1]) * sx) / sxx;
                            else
                                aopt[2] = r2s[l];
                        } else { /* good pixel option use nonlinear */
                            /* init S0 */
                            aavg[1] = s0[l];
                            amin[1] = 0.2 * aavg[1];
                            amax[1] = 2.0 * aavg[1];

                            /* init r2s in units of 1/sec */
                            aavg[2] = r2s[l];
                            amin[2] = 0.2 * aavg[2];
                            amax[2] = 2.0 * aavg[2];

                            /* init lista */
                            nparam = 2;
                            for (i = 1; i <= nparam; i++) {
                                lista[i] = 2;
                                asig[i] = (amax[i] - amin[i]) / 4.0;
                            }
                            logp =
                                pixelr2s(nparam, NTE, x, y, aopt, aostd, lista, aavg, asig, amin, amax, covar, alpha);
                        }

                    }

                    /* regularization with mean values */
                    else if (regular_flag != 0) {
                        if (regular_flag == 2)
                            aopt[1] = s0[l];
                        else
                            aopt[1] = ss0 / npix2; /* use avg */

                        sxy = 0.0;
                        xc = 0;
                        for (i = 1; i <= NTE; i++) {
                            if (y[i] > 0.0) {
                                xc++;
                                lny[i] = log(y[i]);
                                sxy = sxy + x[i] * lny[i];
                            }
                        }

                        if (xc >= 2)
                            aopt[2] = -(sxy - log(aopt[1]) * sx) / sxx;
                        else
                            aopt[2] = r2s[l];
                    }

                    /* Error checking on output */
                    /* Bad NaN, Inf pathology, need to exit */
                    if (!isfinite(aopt[1]) || !isfinite(aopt[2])) {
                        printf("\n 4th pixel %d bad %d s0 r2s %f %f y = %f %f %f %f\n", jndex, badpix[l], aopt[1],
                               aopt[2], y[1], y[2], y[3], y[4]);
						mask1[jndex] = 1;
                        imgQA[jndex + 2*vdim] = 1;
                        imgQA[jndex + 3*vdim] = 1;
						continue;
                    }
                    /* Final check and repair minor pathology */
                    else if (aopt[1] <= 0.0 || aopt[2] <= 0.0) {
                        aopt[1] = ss0 / npix2;
                        aopt[2] = sr2 / npix2;
                    }

                    /* STORE params for output, S0, R2*, calculated S */
                    s0[l] = aopt[1];
                    r2s[l] = aopt[2];
                    img1[l * vdim + jndex] = aopt[1];
                    img2[l * vdim + jndex] = aopt[2];

                    /* store improved Sfit, but test for outliers first */
                    ssum2 = r2s_make(tefit, aopt);
                    if (ssum2 < avgs0[2] + 3.0 * stds0[2] && ssum2 > avgs0[2] - 3 * stds0[2]) {
                        img6[l * vdim + jndex] = ssum2;
                    }
                    /* if outlier replace with original value 2nd echo */
                    else {
                        /*	img6[l*vdim + jndex] = (imgtn + tedim + l*vdim)[jndex];	*/
                        img6[l * vdim + jndex] = imgsn[j][l][1];
                    }

                    /* STORE the residual error */
                    sumr2 = 0.0;
                    for (i = 1; i <= NTE; i++) {
                        sumr2 += (y[i] - r2s_make(x[i], aopt)) * (y[i] - r2s_make(x[i], aopt));
                    }
                    /* 3th output volume is residual error */
                    res[l] = sqrt(sumr2 / NTE);
                    img3[l * vdim + jndex] = sqrt(sumr2 / NTE);

                } /* end 4th "l" loop on frames */
            }     /* end if on mask */
        }         /* end "j" loop on voxels in each slice */
    }             /* end "k" slice loop */
    printf("\n");

    /***********************************************/
    /* use spatial smoothing for really bad voxels */
    /***********************************************/
    i2 = SSMOOTH;
    j2 = SSMOOTH;
    k2 = 1;
    if (slc_flag) k2 = 0;
    for (k = 1; k < imgdim[2] - 1; k++) {
        if (slc_flag && (slcsel != k)) continue;

        for (j = j2; j < imgdim[1] - j2; j++) {
            for (i = i2; i < imgdim[0] - i2; i++) {
                jndex = k * sdim + j * imgdim[0] + i;

                if (mask1[jndex] == 1) { /* mask of pathological voxels */

                    npix = 0;
                    ss0 = 0.0;
                    sr2 = 0.0;
                    for (l = 0; l < nframe; l++) {
                        s0[l] = 0.0;
                        r2s[l] = 0.0;
                    }
                    for (k1 = -k2; k1 <= k2; k1++) {
                        for (j1 = -j2; j1 <= j2; j1++) {
                            for (i1 = -i2; i1 <= i2; i1++) {
                                jndex1 = (k + k1) * sdim + (j + j1) * imgdim[0] + (i + i1);
                                if (jndex1 == jndex) continue;
                                if (mask[jndex1] == 1 && mask1[jndex1] == 0) {
                                    npix++;
                                    for (l = 0; l < nframe; l++) {
                                        s0[l] += img1[jndex1 + l * vdim];
                                        r2s[l] += img2[jndex1 + l * vdim];
                                    }
                                }
                            }
                        }
                    }

                    if (npix >= 1) { /* successful fix */
                        for (l = 0; l < nframe; l++) {
                            img1[l * vdim + jndex] = s0[l] / npix;
                            img2[l * vdim + jndex] = r2s[l] / npix;

                            /* store improved Sfit, but test for outliers first */
                            ssum2 = (s0[l] / npix) * exp(-tefit * r2s[l] / npix);
                            if (ssum2 < avgs0[2] + 3.0 * stds0[2] && ssum2 > avgs0[2] - 3 * stds0[2]) {
                                img6[l * vdim + jndex] = ssum2;
                            }
                            /* if outlier replace with original value 2nd echo */
                            else {
                                /*	img6[l*vdim + jndex] = (imgtn + tedim + l*vdim)[jndex];	*/
                                img6[l * vdim + jndex] = imgsn[j][l][1];
                            }
                        }
                        imgQA[jndex + 3 * vdim] = 0;
                    } 
                    else { /* failed fix, remove from mask */
                        imgQA[jndex + 1 * vdim] = 0;
                    }
                } /* mask1 */

            } /* i,j loop */
        }
    } /* k loop */

    /****************************************/
    /* close and remove disk image of imgsn */
    /****************************************/
    if (fclose(imgsnfp)) errw(program, tmpfile);
    if (remove(tmpfile)) errw(program, tmpfile);

    /*********************/
    /* write 4dfp output */
    /*********************/
    sprintf(outroot1, "%s_S0", outroot);
    MEfmri_out(outroot1, img1, tedim, ifh, control, nframe, imgroot[0], argc, argv, program);
    sprintf(outroot1, "%s_R2s", outroot);
    MEfmri_out(outroot1, img2, tedim, ifh, control, nframe, imgroot[0], argc, argv, program);
    sprintf(outroot1, "%s_Sfit", outroot);
    MEfmri_out(outroot1, img6, tedim, ifh, control, nframe, imgroot[0], argc, argv, program);
    sprintf(outroot1, "%s_Res", outroot);
    MEfmri_out(outroot1, img3, tedim, ifh, control, nframe, imgroot[0], argc, argv, program);
    sprintf(outroot1, "%s_Swgt", outroot);
    MEfmri_out(outroot1, img5, tedim, ifh, control, nframe, imgroot[0], argc, argv, program);
    sprintf(outroot1, "%s_QC1", outroot);
    MEfmri_out(outroot1, imgQA, NVOL1 * vdim, ifh, control, NVOL1, imgroot[0], argc, argv, program);

    /*********************/
    /* deallocate memory */
    /*********************/
    free_float3(imgsn);
    free(img1);
    free(img2);
    free(img6);
    free(img3);
    free(imgQA);
    free(img5);
    free(mask);
    free(mask1);
    free(badpix);
    free(r2s);
    free(s0);
    free(s0new);
    free(res);
    free(imgS0);
    free(imgR2);
    free(imgwn);

    free_vector(avgs0, 1, NTE);
    free_vector(stds0, 1, NTE);
    free_vector(stdte, 1, NTE);
    free_vector(avgte, 1, NTE);
    free_vector(lny, 1, NTE);
    free_vector(sig, 1, NTE);
    free_matrix(alpha, 1, MAXP, 1, MAXP);
    free_matrix(covar, 1, MAXP, 1, MAXP);
    free_vector(y2, 1, NTE);
    free_vector(y, 1, NTE);
    free_vector(x, 1, NTE);
    free_vector(xb, 1, NTE);
    free_ivector(lista, 1, MAXP);

    return status;
}

/******************************************/
/* pixelr2s - calculate R2* for one pixel */
/******************************************/
float pixelr2s(int nparam, int ndata, float *x, float *y, float *aopt, float *aostd, int *lista, float *aavg,
               float *asig, float *amin, float *amax, float **covar, float **alpha) {
    static long seed = (-47);
    int i, j, k, l, itst, iopt, goodpar, w1;
    float chisqopt, alamda, chisq, ochisq, a[MAXP + 1];

    chisqopt = -9.0e9;
    for (l = 0; l < NPOP; l++) {
        /* loop to create random set of new params */
        w1 = 0;
        do {
            w1++;
            goodpar = 1;
            for (i = 1; i <= nparam; i++) {
                if (lista[i] == 0) a[i] = aavg[i];
                if (lista[i] != 0) do {
                        a[i] = aavg[i] + asig[i] * gasdev(&seed);
                    } while (a[i] >= amax[i] || a[i] <= amin[i]);
            }
            if (w1 > 100) printf("Warning(pixelr2s): too many iteration to make valid param %d\n", w1);
        } while (goodpar == 0);

        alamda = -1.0;
        mrqprior1(x, y, ndata, a, lista, aavg, nparam, covar, alpha, &chisq, &alamda);

        j = 1;
        itst = 0;
        while (itst < NITER) {
            if (PRT_FLG) {
                printf("\n%s %2d %17s %13.4e %10s %9.2e\n", "Iteration #", j, "chi-squared:", chisq, "alamda:", alamda);
                printf("%10s %10s %10s %10s %10s %10s \n", "a[1]", "a[2]", "a[3]", "a[4]", "a[5]", "a[6]");
                for (i = 1; i <= nparam; i++) printf("%11.3e", a[i]);
                printf("\n");
            }
            j++;
            ochisq = chisq;
            mrqprior1(x, y, ndata, a, lista, aavg, nparam, covar, alpha, &chisq, &alamda);
            if (chisq < ochisq)
                itst = 0;
            else if (fabs(ochisq - chisq) < DELCHI)
                itst++;
        }

        alamda = 0.0;
        mrqprior1(x, y, ndata, a, lista, aavg, nparam, covar, alpha, &chisq, &alamda);

        if (PRT_FLG) {
            printf("\nUncertainties:\n");
            for (i = 1; i <= nparam; i++) printf("%11.4f", sqrt(covar[i][i]));
            printf("\n");
        }

        /* store for later, best fit so far */
        if (chisq > chisqopt) {
            /* printf("#%4d lprob %11.3f itr %3d ",l,chisq,j); */
            chisqopt = chisq;
            iopt = l;
            for (i = 1; i <= nparam; i++) {
                aopt[i] = a[i];
                if (covar[i][i] > 0.0)
                    aostd[i] = sqrt(covar[i][i]);
                else
                    aostd[i] = 0.0;
                /* printf("%10.2e\n ",a[i]); */
            }
        }
    } /* end population loop */

    return (chisqopt);
}

/*****************************************************************
** mrqprior1 - improved Levenberg/Marquardt from mrqmin in NR
** 	added relaxation parameter for slower convergence
**		changes involve the relax parameter
**	added ability to use priors for the parameter estimation
*****************************************************************/
void mrqprior1(float x[], float y[], int ndata, float a[], int ia[], float aavg[], int ma, float **covar, float **alpha,
               float *logprob, float *alamda) {
    int j, k, l, m;
    static int mfit;
    static float *da, *atry, **oneda, *beta, ologprob, relax;

    /* initialization */
    if (*alamda < 0.0) {
        atry = vector(1, ma);
        beta = vector(1, ma);
        da = vector(1, ma);
        for (mfit = 0, j = 1; j <= ma; j++)
            if (ia[j]) mfit++;
        oneda = matrix(1, mfit, 1, 1);
        *alamda = 0.001;
        /*
        if (debug_flag) {printf("pre mrqpcof %f %f %d %f %d %f
        %d\n",x[1],y[1],ndata,a[1],ia[1],aavg[1],ma);fflush(stdout);}
        */
        mrqpcof(x, y, ndata, a, ia, aavg, ma, alpha, beta, logprob);
        /*
        if (debug_flag) {printf("post mrqpcof %f %f \n",alpha[1][1], beta[1]); fflush(stdout);}
        */

        ologprob = (*logprob);
        for (j = 1; j <= ma; j++) atry[j] = a[j];
        relax = 1.0e-1; /* original value was 1e-6 */
    }

    /* Alter fitting matrix by augmenting diagonal elements */
    for (j = 0, l = 1; l <= ma; l++) {
        if (ia[l]) {
            for (j++, k = 0, m = 1; m <= ma; m++) {
                if (ia[m]) {
                    k++;
                    covar[j][k] = alpha[j][k];
                }
            }
            covar[j][j] = alpha[j][j] * (1.0 + (*alamda));
            oneda[j][1] = beta[j];
        }
    }

    /* Solve the matrix, return if error  */
    if (gaussj_chk(covar, mfit, oneda, 1)) {
        *logprob = -9.0e9;
        return;
    }

    for (j = 1; j <= mfit; j++) da[j] = oneda[j][1];

    /* finished, evaluate the covariance matrix */
    if (*alamda == 0.0) {
        covsrt(covar, ma, ia, mfit);
        free_matrix(oneda, 1, mfit, 1, 1);
        free_vector(da, 1, ma);
        free_vector(beta, 1, ma);
        free_vector(atry, 1, ma);
        return;
    }

    /* Did the trial succed? */
    for (j = 0, l = 1; l <= ma; l++) {
        if (ia[l]) {
            atry[l] = a[l] + da[++j] * relax;
        }
    }
    mrqpcof(x, y, ndata, atry, ia, aavg, ma, covar, da, logprob);

    /* Accept new solution */
    if (*logprob > ologprob) {
        relax = sqrt(relax);
        *alamda *= 0.1;
        ologprob = (*logprob);
        for (j = 0, l = 1; l <= ma; l++) {
            if (ia[l]) {
                for (j++, k = 0, m = 1; m <= ma; m++) {
                    if (ia[m]) {
                        k++;
                        alpha[j][k] = covar[j][k];
                    }
                }
                beta[j] = da[j];
                a[l] = atry[l];
            }
        }
    }
    /* failure, increase lambda and return */
    else {
        *alamda *= 10.0;
        *logprob = ologprob;
    }
}

/*
** mrqpcof - designed to go with mrqprior
**	does not use sig[] but estimates it from residuals
**	ia[j]==2 add prior based on the following possible functions:
**		log(w/(w0^2 + w^2)) min is 0, peak at w0
**		1.0/(1.0 + exp(-h*(w - w_min))) min is w_min, no peak
**	ia[j]==1 do not add prior
**	ia[j]==0 do not search on this parameter
**	alpha and beta are NOT angles (see NR derivation)
**	factor of -1 is included in the beta calculation
**	There is a factor of 2 cancellation in the alpha, beta calcs
*/
void mrqpcof(float x[], float y[], int ndata, float a[], int ia[], float aavg[], int ma, float **alpha, float beta[],
             float *logprob) {
    int i, j, k, l, m, mfit = 0;
    float ymod, sig2i, sig2, dy, dyda[MAXP + 1];
    double den, anrm, anl, h = 2.0; /* h is transition const for prior function 2 */

    /* dyda = vector(1,ma); */
    /* initialization */
    for (j = 1; j <= ma; j++)
        if (ia[j]) mfit++;
    for (j = 1; j <= mfit; j++) {
        for (k = 1; k <= j; k++) alpha[j][k] = 0.0;
        beta[j] = 0.0;
    }

    /* loop over data, calculate the likelihood function */
    sig2 = 0.0;

    for (i = 1; i <= ndata; i++) {
        r2sfunc(x[i], a, &ymod, dyda, ma);
        dy = y[i] - ymod;
        sig2 += dy * dy;

        for (j = 0, l = 1; l <= ma; l++) {
            if (ia[l]) {
                for (j++, k = 0, m = 1; m <= l; m++)
                    if (ia[m]) alpha[j][++k] += dyda[l] * dyda[m];
                beta[j] += dy * dyda[l];
            }
        }
    }

    (*logprob) = -((float)ndata / 2.0) * log(sig2 / 2.0);

    /* normalize with 1/sig2 and add prior */
    sig2i = (float)ndata / sig2;
    for (j = 0, l = 1; l <= ma; l++) {
        if (ia[l]) {
            j++;
            den = aavg[j] * aavg[j] + a[j] * a[j];
            anrm = a[j] / aavg[j];
            anl = a[j] * (PI / 4.0) / aavg[j];
            for (k = 0, m = 1; m <= l; m++) {
                if (ia[m]) {
                    ++k;
                    alpha[j][k] *= sig2i;
                    /* function 1 2nd derivative  */
                    if (j == k && ia[j] == 2)
                        alpha[j][k] += (4.0 * a[j] * a[j] / (den * den) - 2.0 / den - 1.0 / (a[j] * a[j]));

                    /* function 2 2nd derivative
                    if (j==k && ia[j]==2) alpha[j][k] += -h*exp(-h*anrm)/((1.0+exp(-h*anrm))*(1.0+exp(-h*anrm)));
                    */
                    /* function 3 2nd derivative
                    if (j==k && ia[j]==2) alpha[j][k] += -4.0*h*h*cosh(2.0*h*anrm)/(sinh(2.0*h*anrm)*sinh(2.0*h*anrm));
                    */
                    /* function 4 2nd derivative
                    if (j==k && ia[j]==2) alpha[j][k] += -h*h/(sin(h*anl)*sin(h*anl));
                    */
                }
            }
            beta[j] *= sig2i;

            /* function 1 1st derivative */
            if (ia[j] == 2) beta[j] += -(1.0 / a[j] - 2.0 * a[j] / den);

            /* function 2 1st derivative
            if (ia[j]==2) beta[j] += -(h*exp(-h*anrm)/(1.0 + exp(-h*anrm)));
            */
            /* function 3 1st derivative
            if (ia[j]==2) beta[j] += -(2.0*h/sinh(2.0*h*anrm));
            */
            /* function 4 1st derivative
            if (ia[j]==2) beta[j] += -(h/tan(h*anl));
            */

            /* function 1  */
            if (ia[j] == 2) (*logprob) += log(a[j] / den);

            /* function 2
            if (ia[j]==2) (*logprob) += log(1.0/(1.0 + exp(-h*anrm)));
            */
            /* function 3 using hyperbolic tangent
            if (ia[j]==2) (*logprob) += log(tanh(h*anrm));
            */
            /* function 4 using sin
            if (ia[j]==2) (*logprob) += log(sin(h*anl));
            */
        }
    }

    /* copy to symmetric matrix */
    for (j = 2; j <= mfit; j++)
        for (k = 1; k < j; k++) alpha[k][j] = alpha[j][k];
}

/* invert a matrix using gauss jordan method NR p. 36 */
/* return flag=1 if singular matrix, otherwise return 0 */
int gaussj_chk(float **a, int n, float **b, int m) {
    int *indxc, *indxr, *ipiv;
    int i, icol, irow, j, k, l, ll, status;
    float big, dum, pivinv, temp;
    float swap;

    status = 0;
    indxc = ivector(1, n);
    indxr = ivector(1, n);
    ipiv = ivector(1, n);

    for (j = 1; j <= n; j++) ipiv[j] = 0;
    for (i = 1; i <= n; i++) {
        big = 0.0;
        for (j = 1; j <= n; j++) {
            if (ipiv[j] != 1) {
                for (k = 1; k <= n; k++) {
                    if (ipiv[k] == 0) {
                        if (fabs(a[j][k]) >= big) {
                            big = fabs(a[j][k]);
                            irow = j;
                            icol = k;
                        }
                    } else if (ipiv[k] > 1) {
                        status = 1;
                        goto FREE;
                    }
                }
            }
        }
        ++(ipiv[icol]);
        if (irow != icol) {
            for (l = 1; l <= n; l++) {
                swap = a[irow][l];
                a[irow][l] = a[icol][l];
                a[icol][l] = swap;
            }
            for (l = 1; l <= m; l++) {
                swap = b[irow][l];
                b[irow][l] = b[icol][l];
                b[icol][l] = swap;
            }
        }
        indxr[i] = irow;
        indxc[i] = icol;
        if (a[icol][icol] == 0.0) {
            status = 1;
            goto FREE;
        }
        pivinv = 1.0 / a[icol][icol];
        a[icol][icol] = 1.0;
        for (l = 1; l <= n; l++) a[icol][l] *= pivinv;
        for (l = 1; l <= m; l++) b[icol][l] *= pivinv;
        for (ll = 1; ll <= n; ll++) {
            if (ll != icol) {
                dum = a[ll][icol];
                a[ll][icol] = 0.0;
                for (l = 1; l <= n; l++) a[ll][l] -= a[icol][l] * dum;
                for (l = 1; l <= m; l++) b[ll][l] -= b[icol][l] * dum;
            }
        }
    }
    for (l = n; l >= 1; l--) {
        if (indxr[l] != indxc[l]) {
            for (k = 1; k <= n; k++) {
                swap = a[k][indxr[l]];
                a[k][indxr[l]] = a[k][indxc[l]];
                a[k][indxc[l]] = swap;
            }
        }
    }
FREE:
    free_ivector(ipiv, 1, n);
    free_ivector(indxr, 1, n);
    free_ivector(indxc, 1, n);
    return (status);
}

/* Based on "fit" to a straight line, NR page 665 y = a + b*x */
/* expects the usual inputs + a regularized intercept "a" as input, then returns better slope "b" */
void fitreg(float x[], float y[], int ndata, float sig[], int mwt, float a, float *b) {
    int i;
    float wt, sx = 0.0, sy = 0.0, ss, sxx = 0.0, sxy = 0;

    *b = 0;
    if (mwt) {
        ss = 0.0;
        for (i = 1; i <= ndata; i++) {
            wt = 1.0 / (sig[i] * sig[i]);
            ss += wt;
            sx += x[i] * wt;
            sy += y[i] * wt;
            sxx += x[i] * x[i] * wt;
            sxy += x[i] * y[i] * wt;
        }
    } else {
        for (i = 1; i <= ndata; i++) {
            sx += x[i];
            sy += y[i];
            sxx += x[i] * x[i];
            sxy += x[i] * y[i];
        }
        ss = ndata;
    }
    *b = (sxy - a * sx) / sxx;
}

/* Mode finding program */
/* input array s of values and ndata number of values */
/* function returns mode and std as a separate parameter */
float mode(float s[], int ndata, float *std) {
    int i, imax, imin;
    int h, nbin;
    float mode1, smax = -1.0e9, smin = 1.0e9;

    for (i = 0; i < ndata; i++) {
        if (s[i] >= smax) {
            smax = s[i];
            imax = i;
        }
        if (s[i] <= smin) {
            smin = s[i];
            imin = i;
        }
    }

    if (ndata <= 100)
        nbin = 10;
    else if (ndata <= 1000)
        nbin = 50;
    else
        nbin = 100;

    h = def_hist("hist1", nbin, smin - 1, smax + 1);

    for (i = 0; i < ndata; i++) {
        add_hist(h, s[i], 1.0);
    }

    calc_hist_noprt(h);
    *std = get_std_in(h);
    mode1 = get_mode(h);
    reset_hist();

    /*
    printf("mode %d %f %f %f %f\n",h,*std,mode1,smin,smax);
    */

    return (mode1);
}
