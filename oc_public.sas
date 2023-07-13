libname libname 'path';
run;

data abc_data (keep=subjectid visit aval paramcd chg1-chg3);
	set libname.data;
	if visit in ('Baseline', 'Month 12/15', 'Month 24', 'Month 36') and paramcd in ('Antibody1', 'Antibody2', 'Antibody3');
run;


%macro sortem(tables,byvar);
%local i n table;
%let n=%sysfunc(countw(&tables));
%do i=1 %to &n;
   %let table=%scan(&tables,&i);
   proc sort data=&table;
   by &byvar;
   run;
%end;
%mend;

%macro stats_info(avar= );
PROC UNIVARIATE data=adeff_data noprint;
	VAR &avar;
    CLASS paramcd visit;
    OUTPUT OUT=summaryStats
        N= Count
        MEAN= Mean
        STD= Std
        MEDIAN= Median
        Q1=Q1
        Q3=Q3;
	WHERE &avar ne .;
RUN;

data new_var(drop=Mean Std Median Q1 Q3); 
set summaryStats;
	Mean_Std = CATS(PUT(Mean, 5.1), '±', PUT(Std, 5.2));
	Median_ICR = CATS(PUT(Median, 5.1),'(',PUT(Q1, 5.1), ',',PUT(Q3, 5.1), ')');
run;

ods select none;
ods trace on;
ods output BasicIntervals=CI_means_&avar;

PROC UNIVARIATE data=adeff_data cibasic;
    VAR &avar;
    CLASS paramcd visit;
    output out=CI_median_&avar pctlpts=50 pctlpre=p
          CIPCTLDF=(lowerpre=LCL upperpre=UCL);    
RUN;
ods trace off;
ods select all;

data CI_means_1(drop= Parameter Estimate lowerCL upperCL);
set CI_means_&avar;
if Parameter = 'Mean'; 
	CI_mean = CATS(PUT(lowerCL, 5.1),', ', put(upperCL, 5.1));
run; 

data CI_median_1;
set CI_median_&avar;
	CI_median = CATS(PUT(LCL50, 5.1),', ', put(UCL50, 5.1));
run;

%sortem(new_var CI_means_1 CI_median_1, paramcd);

proc transpose data= new_var out=summaryStats_&avar(drop=_LABEL_);
	by paramcd;
	var Count Mean_Std Median_ICR;
	id visit;
run;

proc transpose data= CI_means_1 out=CI_means_&avar;
	by paramcd;
	var CI_mean;
	id visit;
run;

proc transpose data= CI_median_1 out=CI_median_&avar;
	by paramcd;
	var CI_median;
	id visit;
run;

******;
%sortem(summaryStats_&avar CI_means_&avar CI_median_&avar, paramcd);

data merged_&avar;
set summaryStats_&avar  CI_means_&avar CI_median_&avar;
by paramcd;
paramcd = CATS(paramcd, '_', "&avar");
run;

/* proc print data=merged_&avar; */
/* title "Merged_&avar"; */
/* run; */
%mend stats_info;

%stats_info(avar= aval);
%stats_info(avar= chg1);
%stats_info(avar= chg3);

********************************Pvalue;
proc surveyselect data=adeff_data out=outboot
	seed = 71223
	method=urs
	samprate=1 outhits reps=1000;
run;

proc means data=outboot noprint;
	class paramcd visit;
	var aval;
	OUTPUT OUT=stats_outboot
        MEAN= Mean_boot
        MEDIAN= Median_boot;
run;

PROC UNIVARIATE data=stats_outboot;
	var Mean_boot Median_boot;
RUN;

***********************************end;
%sortem(merged_aval merged_chg1 merged_chg3, paramcd);

data merged_all;
set merged_aval merged_chg1 merged_chg3;
by paramcd;
run;

/* proc print data=merged_all; */
/* title "merged_all_marco"; */
/* run; */

****Header;
proc sql;
    create table header as
    select distinct paramcd
    from merged_all;
quit;

/* proc print data=header; */
/* run; */

data header_label(rename=(paramcd=Variable));
set header;
	ord = _n_;
	if index(paramcd, 'aval') then paramcd = upcase(substr(paramcd, 1, index(paramcd, '_aval')-1));
	else if index(paramcd, 'chg1') then paramcd = "Change from Baseline in " || upcase(substr(paramcd, 1, index(paramcd, '_chg1')-1));
    else if index(paramcd, 'chg3') then paramcd = "Change from Month 12/15 in " || upcase(substr(paramcd, 1, index(paramcd, '_chg3')-1));
run;

/* proc print data=header_label; */
/* run; */

data main_content(drop=PARAMCD _Name_);
set merged_all;
/* 	ord = (int((_n_-1)/5) + 1 + mod((_n_-1), 5) / 10) + 0.1; */
	ord = int((_n_-1)/5) + 1;
	length Variable $50;

	if _Name_ = 'Count' then do; Variable = "        n"; ord + .1; end;
    else if _Name_ = 'Mean_Std' then do; Variable = "        Mean ± SD"; ord + .2; end;
    else if _Name_ = 'CI_mean' then do; Variable = "        95% CI of Mean"; ord + .3; end;
    else if _Name_ = 'Median_ICR' then do; Variable = "        Median(IQR)"; ord +.5; end;
    else if _Name_ = 'CI_median' then do; Variable = "        95% CI of Median"; ord + .6; end;
run;

data merged_data;
set header_label main_content;
run;

PROC SORT DATA=merged_data;
BY ORD;
RUN;

data table_frame(drop=ord);
set merged_data;
run;

ods pdf file='path/report.pdf';
proc print data=table_frame noobs;
	title 'TableName';
run;
ods pdf close;