#$Header$
#$Log$
BEGIN {
	ped = "";
	ST = 0;
	dwell = 0;
	n = 1;
	MBfac = 1;
}

ST == 1 {
	sub(/,/,"",$1);
	t[n] = $1 + 0;
	if ($0 ~/\]/) {
		ST = 0;
	} else if (n > 1 && t[n] == t[1]) {
		ST = 0;
		n--;
	} else {
		n++;
	}
}

$1 ~/SliceTiming/ {ST = 1;}

$1 ~/EffectiveEchoSpacing/ {
	sub(/,/,"",$NF);	
	dwell = $NF;
}

$1 ~ /RepetitionTime/ {
	sub(/,/,"",$NF);
	TR = $NF;
}

$1 ~ /MultibandAccelerationFactor/ {
	sub(/,/,"",$NF);	
	MBfac = $NF;
}

$1 ~/PhaseEncodingDirection/ && $1 !~/In/ {
	sub(/,/,"",$NF);
	gsub(/\"/,"",$NF);		
	ped = $NF
}

END {
	for (i = 1; i <= n; i++) u[i] = t[i];
	asort (u);
	printf("set seqstr = ");
	for (i = 1; i <= n; i++) for (j = 1; j <= n; j++) {
		if (t[j] == u[i]) printf("%d,", j);
	}
	printf("\n");
	printf("set MBfac = %s\n", MBfac);
	printf("set TR_vol = %s\n", TR);
	printf("set dwell = %s\n", dwell);
	printf("set pedindex = %s\n", ped);
}

