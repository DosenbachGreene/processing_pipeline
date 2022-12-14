/* header file for histogram routines */

int def_hist(char *name, int num_bin, float minval, float maxval);
void reset_hist();
void add_hist(int num_hist, float value, float weight);
void calc_hist(int num_hist);
void calc_hist_noprt(int num_hist);
float get_avg_in(int num_hist);
float get_std_in(int num_hist);
float get_median(int num_hist);
float get_mode(int num_hist);
void out_hist(int num_hist, char *file);
void print_hist(int num_hist);
void matlab_hist(int num_hist, char *file);
void clr_hist(int num_hist);
void dump_hist(int num_hist);
void out_plot(int num, float *data, char *file, float ymin, float ymax);
void out_plot2(int num, float *data1, float *data2, char *file, float ymin, float ymax);


