#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

/* 
** histogram package
*/

#define	MEMSIZE	2000
#define MAXHIST 20

typedef struct hist_data {
    int num_bin, ind_bin;
    float minval,maxval,binsize;
    int iunder,iin,iover;
    float under,in,over;
    float sum_in, sum2_in;
    float sum_all, sum2_all;
    float avg_in, std_in;
    float avg_all, std_all;
    float median, mode;
    char name[32];
    int calc_err;
} HIST;

float	hdat[MEMSIZE];
HIST	hist[MAXHIST];
static int next_hist=0, next_index=0;

/*
** def_hist - define new histogram
** input: name, number of bins and min and max values
** returns: histogram number
*/
int def_hist(char *name, int num_bin, float minval, float maxval)
{
    int num_hist, i;

    if (num_bin<=0) {
	printf("ERROR: illegal number of bins\n");
	return(-1);
    }
    num_hist = next_hist;
    ++next_hist;
    if (next_hist > MAXHIST) {
	printf("ERROR: too many histograms\n");
	return(-1);
    }
    hist[num_hist].num_bin = num_bin;
    hist[num_hist].ind_bin = next_index;
    next_index += num_bin;
    if (next_index > MEMSIZE) {
	printf("ERROR: not enough memory for new histogram\n");
	return(-1);
    }

    hist[num_hist].minval = minval;
    hist[num_hist].maxval = maxval;
    hist[num_hist].binsize = (maxval-minval)/num_bin;
/* init to zero */
    hist[num_hist].iunder = 0;
    hist[num_hist].iin = 0;
    hist[num_hist].iover = 0;
    hist[num_hist].under = 0.0;
    hist[num_hist].in = 0.0;
    hist[num_hist].over = 0.0;
    hist[num_hist].sum_in = 0.0;
    hist[num_hist].sum2_in = 0.0;
    hist[num_hist].sum_all = 0.0;
    hist[num_hist].sum2_all = 0.0;
    hist[num_hist].median = 0.0;
    hist[num_hist].mode = 0.0;
    hist[num_hist].calc_err = 0;
    for (i=0; i<num_bin; ++i) 
	hdat[hist[num_hist].ind_bin+i] = 0.0;
/* copy name */
    strcpy(hist[num_hist].name, name);
    return(num_hist);
}

/*
** reset_hist() - reset all histograms, erase all data
*/
void reset_hist()
{
	next_hist = 0;
	next_index = 0;
}

/* 
** add_hist - add new element to existing histogram
*/
void add_hist(int num_hist, float value, float weight)
{
    int ind_bin;
    float minval, binsize;

/* check error */
    if (num_hist>=next_hist || num_hist<0) {
	printf("ERROR: no such histogram\n");
	return;
    }
/* under flow */
    if (value < hist[num_hist].minval) {
	hist[num_hist].iunder += 1;
	hist[num_hist].under += weight;
	hist[num_hist].sum_all += value*weight;
	hist[num_hist].sum2_all += value*value*weight*weight;
	return;
    }
/* over flow */
    if (value > hist[num_hist].maxval) {
	hist[num_hist].iover += 1;
	hist[num_hist].over += weight;
	hist[num_hist].sum_all += value*weight;
	hist[num_hist].sum2_all += value*value*weight*weight;
	return;
    }
/* in range */
    hist[num_hist].iin += 1;
    hist[num_hist].in += weight;
    hist[num_hist].sum_all += value*weight;
    hist[num_hist].sum2_all += value*value*weight*weight;
    hist[num_hist].sum_in += value*weight;
    hist[num_hist].sum2_in += value*value*weight*weight;

    ind_bin = hist[num_hist].ind_bin;
    minval = hist[num_hist].minval;
    binsize = hist[num_hist].binsize;

    hdat[ind_bin + (int)((value-minval)/binsize)] += weight;
}


/*
** calc_hist - calculate averages and std's
*/
void calc_hist(int num_hist)
{
    float n, num, maxval, midval;
    int i, imax, imid;

/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(calc_hist): %d no such histogram\n",num_hist);
		return;
    }

    n = hist[num_hist].in;

/* div error check */
    if (n <= 1.0) {
		printf("Error(calc_hist): %d no entries in range\n",num_hist);
		hist[num_hist].calc_err = 1;
		return;
    }
    else hist[num_hist].avg_in = hist[num_hist].sum_in / n;

/* sqrt negative number check */
    num = hist[num_hist].sum2_in - 
	hist[num_hist].sum_in*hist[num_hist].sum_in/n;
    if (num < 0.0) num = 0.0; /* roundoff effect */
    hist[num_hist].std_in = sqrt(num/(n-1.0));

    n = hist[num_hist].in + hist[num_hist].over + hist[num_hist].under;

/* div error check */
    if (n <= 1.0) {
		printf("ERROR: %d no entries\n",num_hist);
		hist[num_hist].calc_err = 1;
		return;
    }
    hist[num_hist].avg_all = hist[num_hist].sum_all / n;

/* sqrt negative number check */
    num = hist[num_hist].sum2_all - 
	hist[num_hist].sum_all*hist[num_hist].sum_all/n;
    if (num < 0.0) num = 0.0; /* roundoff effect */
    hist[num_hist].std_all = sqrt(num/(n-1.0));

/* get median and mode */
/* find the median and largest bin value */
    maxval = hdat[hist[num_hist].ind_bin];
    imax = imid = 0;
    midval = 0.0;
    for (i=0; i<hist[num_hist].num_bin; ++i) {
		if (hdat[hist[num_hist].ind_bin+i] > maxval) {
			maxval = hdat[hist[num_hist].ind_bin+i];
			imax = i;
		}
		midval += hdat[hist[num_hist].ind_bin+i];
		if (imid==0 && midval > hist[num_hist].in/2.0) imid = i;
    }
	hist[num_hist].median = hist[num_hist].minval + hist[num_hist].binsize*((float)imid+0.5);
	hist[num_hist].mode   = hist[num_hist].minval + hist[num_hist].binsize*((float)imax+0.5);

/* print out section */
    printf("----------------------------------------------------\n");
    printf("historgram: %d %s     num bins: %d\n",num_hist,hist[num_hist].name, hist[num_hist].num_bin);
    printf("min val %9.4f max val %9.4f\n",
	hist[num_hist].minval, hist[num_hist].maxval);
    printf("weighted entries under %9.4f in %9.4f over %9.4f\n",
	hist[num_hist].under, hist[num_hist].in, hist[num_hist].over);
    printf("in  entries avg %12.4e std %12.4e\n",
	hist[num_hist].avg_in, hist[num_hist].std_in);
    printf("all entries avg %12.4e std %12.4e\n",
	hist[num_hist].avg_all, hist[num_hist].std_all);
	printf("median %12.4e mode %12.4e\n",
	hist[num_hist].median, hist[num_hist].mode);
}


/*
** calc_hist_noprt - calculate averages and std's
*/
void calc_hist_noprt(int num_hist)
{
    float n, num, maxval, midval;
    int i, imax, imid;

/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(calc_hist): %d no such histogram\n", num_hist);
		return;
    }

    n = hist[num_hist].in;

/* div error check */
    if (n <= 1.0) {
		hist[num_hist].calc_err = 1;
		return;
    }
    hist[num_hist].avg_in = hist[num_hist].sum_in / n;

/* sqrt negative number check */
    num = hist[num_hist].sum2_in - 
	hist[num_hist].sum_in*hist[num_hist].sum_in/n;
    if (num < 0.0) num = 0.0; /* roundoff effect */
    hist[num_hist].std_in = sqrt(num/(n-1.0));

    n = hist[num_hist].in + hist[num_hist].over + hist[num_hist].under;

/* div error check */
    if (n <= 1.0) {
		hist[num_hist].calc_err = 1;
		return;
    }
    hist[num_hist].avg_all = hist[num_hist].sum_all / n;

/* sqrt negative number check */
    num = hist[num_hist].sum2_all - 
	hist[num_hist].sum_all*hist[num_hist].sum_all/n;
    if (num < 0.0) num = 0.0; /* roundoff effect */
    hist[num_hist].std_all = sqrt(num/(n-1.0));

/* get median and mode */
/* find the median and largest bin value */
    maxval = hdat[hist[num_hist].ind_bin];
    imax = imid = 0;
    midval = 0.0;
    for (i=0; i<hist[num_hist].num_bin; ++i) {
		if (hdat[hist[num_hist].ind_bin+i] > maxval) {
			maxval = hdat[hist[num_hist].ind_bin+i];
			imax = i;
		}
		midval += hdat[hist[num_hist].ind_bin+i];
		if (imid==0 && midval > hist[num_hist].in/2.0) imid = i;
    }
	hist[num_hist].median = hist[num_hist].minval + hist[num_hist].binsize*((float)imid+0.5);
	hist[num_hist].mode   = hist[num_hist].minval + hist[num_hist].binsize*((float)imax+0.5);

}


/* 
** out_hist - print out histogram in file form for further display
** 	prints histogram sideways with *******
*/
void out_hist(int num_hist, char *file)
{
    int i,j, mxstar=30;
    float imax, imin, scale;
    FILE *fp;

/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(out_hist): %d no such histogram\n",num_hist);
		return;
    }
    
/* check error in calculation */
	if (hist[num_hist].calc_err) {
		printf("Error(out_hist): %d calculation error\n",num_hist);
		return;
	}
	
/* find the largest and smallest bin value */
    imin = hdat[hist[num_hist].ind_bin];
    imax = hdat[hist[num_hist].ind_bin];
    for (i=0; i<hist[num_hist].num_bin; ++i) {
	if (hdat[hist[num_hist].ind_bin+i] < imin)
		imin = hdat[hist[num_hist].ind_bin+i];
	if (hdat[hist[num_hist].ind_bin+i] > imax)
		imax = hdat[hist[num_hist].ind_bin+i];
    }
    scale = (imax - imin)/mxstar;

/* open the file */
    fp = fopen(file, "w");
    if (fp == 0) printf("Error(out_hist): %d can't open file\n",num_hist);

    fprintf(fp,"\n");
/* loop over the bins */
    for (i=0; i<hist[num_hist].num_bin; ++i) {
/* print the bin information */
	fprintf(fp, "%12.4e %12.4e ", 
	hist[num_hist].minval+i*hist[num_hist].binsize,
	hdat[hist[num_hist].ind_bin + i]);
/* this part prints the histogram if scale is ok */
	if (scale > 0.0) {
	for (j=0; j<(int)((hdat[hist[num_hist].ind_bin + i] - imin)/scale); ++j)
		fprintf(fp,"*");
	}
	fprintf(fp,"\n");
    }
    fclose(fp);
}

/* 
** print_hist - print out histogram as text to screen
*/
void print_hist(int num_hist)
{
    int i,j;

/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(print_hist): %d no such histogram\n",num_hist);
		return;
    }
    
/* check error in calculation */
	if (hist[num_hist].calc_err) {
		printf("Error(print_hist): %d calculation error\n",num_hist);
		return;
	}
	
	printf("HISTOGRAM #%d: %s\n",num_hist, hist[num_hist].name);
	printf("--------------------------------\n");

/* loop over the bins */
    for (i=0; i<hist[num_hist].num_bin; ++i) {
		printf("%3d %12.4e %12.4e\n", i,
		hist[num_hist].minval+i*hist[num_hist].binsize,
		hdat[hist[num_hist].ind_bin + i]);
	}

}

/*
** routines to get calculated values for other computations
*/
float get_avg_in(int num_hist)
{
/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(get_avg_in): %d no such histogram\n",num_hist);
		return 0.0;
    }
    
/* check error in calculation */
	if (hist[num_hist].calc_err) {
		printf("Error(get_avg_in): %d calculation error\n",num_hist);
		return 0.0;
	}

	return hist[num_hist].avg_in;
}

float get_std_in(int num_hist)
{
/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(get_std_in): %d no such histogram\n",num_hist);
		return 0.0;
    }
    
/* check error in calculation */
	if (hist[num_hist].calc_err) {
		printf("Error(get_std_in): %d calculation error\n",num_hist);
		return 0.0;
	}
	
	return hist[num_hist].std_in;
}

float get_median(int num_hist)
{
/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(get_std_in): %d no such histogram\n",num_hist);
		return 0.0;
    }
    
/* check error in calculation */
	if (hist[num_hist].calc_err) {
		printf("Error(get_std_in): %d calculation error\n",num_hist);
		return 0.0;
	}
	
	return hist[num_hist].median;
}

float get_mode(int num_hist)
{
/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(get_std_in): %d no such histogram\n",num_hist);
		return 0.0;
    }
    
/* check error in calculation */
	if (hist[num_hist].calc_err) {
		printf("Error(get_std_in): %d calculation error\n",num_hist);
		return 0.0;
	}
	
	return hist[num_hist].mode;
}


/*
** clr_hist - clear previously defined histogram
** input: name, number of bins and min and max values
** returns: histogram number
*/
void clr_hist(int num_hist)
{
    int i;

/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
	printf("ERROR: no such histogram\n");
	return;
    }

/* init to zero */
    hist[num_hist].iunder = 0;
    hist[num_hist].iin = 0;
    hist[num_hist].iover = 0;
    hist[num_hist].under = 0.0;
    hist[num_hist].in = 0.0;
    hist[num_hist].over = 0.0;
    hist[num_hist].sum_in = 0.0;
    hist[num_hist].sum2_in = 0.0;
    hist[num_hist].sum_all = 0.0;
    hist[num_hist].sum2_all = 0.0;
    hist[num_hist].median = 0.0;
    hist[num_hist].mode = 0.0;
    hist[num_hist].calc_err = 0;
    for (i=0; i<hist[num_hist].num_bin; ++i) 
	hdat[hist[num_hist].ind_bin+i] = 0.0;

}

/*
** dump_hist - dump histogram memory for error checking
*/
void dump_hist(int num_hist)
{
    float n, num;

/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(dump_hist): no such histogram\n");
		return;
    }
    
    printf("dump histogram %d ----------------\n", num_hist);
    printf("num_bin %d ind_bin  %d \n",hist[num_hist].num_bin,hist[num_hist].ind_bin);
    printf("minval  %f maxval   %f binsize %f\n",hist[num_hist].minval,hist[num_hist].maxval,hist[num_hist].binsize);
    printf("iunder  %d iin      %d iover   %d\n",hist[num_hist].iunder,hist[num_hist].iin,hist[num_hist].iover);
    printf("under   %f in       %f over    %f\n",hist[num_hist].under,hist[num_hist].in,hist[num_hist].over);
    printf("sum_in  %e sum2_in  %e\n",hist[num_hist].sum_in, hist[num_hist].sum2_in);
    printf("sum_all %e sum2_all %e\n",hist[num_hist].sum_all,hist[num_hist].sum2_all);
    printf("avg_in  %e std_in   %e\n",hist[num_hist].avg_in,hist[num_hist].std_in);
    printf("avg_all %e std_all  %e\n",hist[num_hist].avg_all,hist[num_hist].std_all);
	printf("median  %e mode     %e\n",hist[num_hist].median,hist[num_hist].mode);
    printf("name    %s calc_err %d\n",hist[num_hist].name, hist[num_hist].calc_err);
    printf("dump histogram %d ----------------\n", num_hist);

	return;
}

/* 
** matlab_hist - print out histogram in file form for matlab display
**	similar to print_hist with output routed to file
*/
void matlab_hist(int num_hist, char *file)
{
    int i;
    FILE *fp;

/* check error in hist number */
    if (num_hist>=next_hist || num_hist<0) {
		printf("Error(out_hist): %d no such histogram\n",num_hist);
		return;
    }
    
/* check error in calculation */
	if (hist[num_hist].calc_err) {
		printf("Error(out_hist): %d calculation error\n", num_hist);
		return;
	}

/* open the file */
    fp = fopen(file, "w");

/* print title, number of bins, avg_in, std_in */
    fprintf(fp, "%s\n", hist[num_hist].name);
    fprintf(fp, "%d\n", hist[num_hist].num_bin);
    fprintf(fp, "%10.3f\n", hist[num_hist].avg_in);
    fprintf(fp, "%10.3f\n", hist[num_hist].std_in);

/* loop over the bins */
    for (i=0; i<hist[num_hist].num_bin; ++i) {
/* print the bin information */
		fprintf(fp, "%12.4e %12.4e\n", 
			hist[num_hist].minval+i*hist[num_hist].binsize,
			hdat[hist[num_hist].ind_bin + i]);
    }
    fclose(fp);
}


/* 
** out_plot, out_plot2 - print out a single or double plot to file
**	independent from histogram routines
** input:
**	num: number of data points, less than 100
**	data: array with data to be plotted
**	file: output file
**	ymin, ymax: if !=0 determines the plot limits
*/
void out_plot(int num, float *data, char *file, float ymin, float ymax)
{
	int	i,j;
	int	*drow;
	int	ysize=50, xsize=120;
	float	max, min, scale; 
	FILE	*fp;

	if (num >= xsize) {
		printf("Error(out_plot): too many data points\n");
		return;
	}

	/* allocate memory, drow:convert data to row number, nrow: number points in row */
	drow = (int *)malloc(num*sizeof(int));

	/* get scale */
	if (ymin != 0.0 || ymax != 0.0) {
		min = ymin;
		max = ymax;
	}
	else for (i=0; i<num; i++) {
		if (data[i] > max) max = data[i];
		if (data[i] < min) min = data[i];
	}
	scale = (max - min)/(float)ysize;

	/* fill drow and nrow */
	for (i=0; i<num; i++) {
		drow[i] = ysize - 1 - (int)((data[i]-min)/scale);
	}

	/* open the file */
	fp = fopen(file, "w");
	/* print out the plot */
	for (i=0; i<ysize; i++) {
		fprintf(fp,"%12.4e|",max - (i+1)*scale);
		for (j=0; j<num; j++) {
			if (drow[j] == i) fprintf(fp,"*");
			else fprintf(fp," ");
		}
		fprintf(fp,"\n");
	}
	/* horizontal axis */
	fprintf(fp,"             ");
	for (i=0; i<num; i++) fprintf(fp,"%d",(int)i/10);
	fprintf(fp,"\n");
	fprintf(fp,"             ");
	for (i=0; i<num; i++) fprintf(fp,"%d",i%10);
	fprintf(fp,"\n");

	fclose(fp);
	free(drow);
	return;
}


void out_plot2(int num, float *data1, float *data2, char *file, float ymin, float ymax)
{
	int	i,j;
	int	*drow, *nrow;
	int	ysize=50, xsize=120;
	float	max, min, scale; 
	FILE	*fp;

	if (num >= xsize) {
		printf("Error(out_plot): too many data points\n");
		return;
	}

	/* allocate memory, drow:convert data to row number, nrow: number points in row */
	drow = (int *)malloc(num*sizeof(int));
	nrow = (int *)malloc(num*sizeof(int));

	/* get scale */
	if (ymin != 0.0 || ymax != 0.0) {
		min = ymin;
		max = ymax;
	}
	else for (i=0; i<num; i++) {
		if (data1[i] > max) max = data1[i];
		if (data1[i] < min) min = data1[i];
		if (data2[i] > max) max = data2[i];
		if (data2[i] < min) min = data2[i];
	}
	scale = (max - min)/(float)ysize;

	/* fill drow and nrow */
	for (i=0; i<num; i++) {
		drow[i] = ysize - 1 - (int)((data1[i]-min)/scale);
		nrow[i] = ysize - 1 - (int)((data2[i]-min)/scale);
printf(" %d %d --",i,drow[i]);
	}

	/* open the file */
	fp = fopen(file, "w");
	/* print out the plot */
	for (i=0; i<ysize; i++) {
		fprintf(fp,"%12.4e|",max - (i+1)*scale);
		for (j=0; j<num; j++) {
			if (drow[j] == i) fprintf(fp,"*");
			else if (nrow[j] == i) fprintf(fp,"+");
			else fprintf(fp," ");
		}
		fprintf(fp,"\n");
	}
	/* horizontal axis */
	fprintf(fp,"             ");
	for (i=0; i<num; i++) fprintf(fp,"%d",(int)i/10);
	fprintf(fp,"\n");
	fprintf(fp,"             ");
	for (i=0; i<num; i++) fprintf(fp,"%d",i%10);
	fprintf(fp,"\n");

	fclose(fp);
	free(drow);
	free(nrow);
	return;
}
