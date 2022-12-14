#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/ncontig_format.awk,v 1.1 2022/11/28 06:07:22 avi Exp $
#$Log: ncontig_format.awk,v $
#Revision 1.1  2022/11/28 06:07:22  avi
#Initial revision
#

BEGIN {
	ncontig = 0;
	n = 0;
	nseg = 0;
	on = 0;
}
NF == 1 {str[n] = $1; n++;}
END {
	if (0) print n
	for (i = 1; i < n; i++) {
		if (str[i] == "+" && on == 0) {
			nseg++;
			start[nseg] = i;
			len[nseg] = 0;
			on++;
		}
		if (on && str[i] == "+") len[nseg]++;
		if (str[i] != "+") on = 0;
	}
	for (j = 1; j <= nseg; j++) {
		if (0) printf ("%5d%5d%5d\n", j, start[j], len[j]);
		if (len[j] < ncontig) {
			for (i = start[j]; i <= start[j] + len[j]; i++) str[i] = "x";
		}
	}
	for (i = 0; i < n; i++) printf ("%c", str[i]);
}
