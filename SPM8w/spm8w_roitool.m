function roidata=spm8w_roitool(varargin) 
% ==============================================================================
% SPM8w r5236
% Script driven batching for SPM8 with additional tools and support for 
% other commonly used analyses (roi, ppi, mixed).
% 
% Heatherton & Kelley Labs
% Last update: March, 2013 - DDW
% Created: May, 2010 - DDW
% ==============================================================================
% function spm8w_roitool('roi_studyname_file', [coordinate], size)
%
% spm8w_roitool is an upgraded and tweaked out version of our get_data_save.m 
% which itself was a leveled-up version of get_data.m. At its core spm8w_roitool
% will extract parameter estimates from a series of con files and saves the
% values to tab delimited txt file pre-formated for importing into stats
% programs.
%
% This version takes only an ROI_studyname.m file as input, all the ROI 
% specifications are made in this file (coordinates, sphere sizes, dir specs 
% etc) including pointers to excel files (i.e. .xlsx files) for roi
% specifications.
%
% Optionally you can provide both the ROI_studyname.m file and a list
% containing a single coordinate i.e., [-20,5,18] and an ROI size). If you 
% provide a single coordiante, this will override the r.roi_specs.
% 
% TO USE: 
% spm8w_roitool()
% spm8w_roitool outputs a single textfile which includes the ROI coordinates, 
% subject names, condition names and parameter estimates. And another text
% file containing results of basic stats.
%
% NOTE:
% If you choose to use the sphere mask genereated by spm8w_roitool
% be aware that this mask is in the space defined by the standard_image.nii
% file. This file is in the same space as our regular pipeline but if you
% decide to resample to a different voxel size or space, the mask will no
% longer be appropriate. You can always verify that the mask is appropriate
% using checkreg with the img files generated by spm8w_roitool.
% ==============================================================================
% CHANGE LOG:
% -Added code to output a verbose textfile -DDW Oct/07
% -Added code to generate spherical ROIs at specified coordinates -JM June/08
% -Added option to specify sphere size -DDW June/08
% -Modified so that output is now a single textfile instead of 
% file/region -DDW Dec/09
% -Converted to spm8 -DDW Jan/10
% -Overhauled getdata to make it more automated and controlled via parameter.m 
%  file -DDW Jan/10
% -Changed name to roitool -DDW Jan/10
% -Added output of basic stats to command window and saved to file -DDW Jan/10
% -Added ability to iterate through multiple correlation vars based on size of 
%  r.roi_corr -DDW July/10
% -Changed the spm_defaults to spm('Defaults','fmri') - DDW Aug/10
% -Changed the way correl and ttest variable files are handled, requires
% new ROI file - DDW April/11
% -Windows compatible -DDW March/12
% -Fixed t-test2 bug -DDW April/12
% -Added group means to t-test2 - DDW Oct/12
% -Removed txt file support in favor of an xls file. Group assignment will
% be made my matching names in the file to variables (much much safer than
% hoping directory order and variable order match!). - DDW March/13
% -Added xls file support for ROI specs if desired - DDW March/13
% -If more than 2 groups, performs between group t-ttests on all possible
% pairs. - DDW March/13
% -Added support for single coordinate. -DDW March/13
% =======1=========2=========3=========4=========5=========6=========7=========8

%---Input checks
switch (nargin)
  case 0 
    r = spm8w_getp('ROI');
  case 1
    r = spm8w_getp('ROI', '', varargin{1}); 
  case 2
    r = spm8w_getp('ROI', '', varargin{1}); 
    %override spec file and roi_specs. Assume roi size of 6mm.
    r.roi_specs = {sprintf('Region: %s',varargin{2})
                   varargin{2}
                   '6'}';
    r.spec_file = '';   
  case 3
    r = spm8w_getp('ROI', '', varargin{1}); 
    %override spec file and roi_specs. Catch in case of image mask(i.e.
    %don't mat2str). 
    if isnumeric(varargin{3})
        radius = mat2str(varargin{3});
    else
        radius = varargin{3};
    end
    r.roi_specs = {sprintf('Regionv: %s', varargin{2})
                   varargin{2} 
                   radius}';
    r.spec_file = '';       
  otherwise
    error('You''ve specified too many inputs. Only specify ROI_para.m file.');
end
cd(r.root)

%---Check directories
%--Make sure all directories exist
if ~isdir(fullfile(r.root,'ROI'))
        mkdir(fullfile(r.root,'ROI'));
        mkdir(r.roi);
elseif ~isdir(r.roi)
        mkdir(r.roi);       
end
%--Check RFX dir
if ~isdir(r.rfx_dir)
    error('It appears the rfx_dir: %s does not exist, please check your paths', r.rfx_dir);
end
%--Check RFX con dirs
for i= 1:size(r.conditions,1)
    if ~isdir(fullfile(r.rfx_dir,r.conditions{i}))
        error('It appears the con dir: %s does not exist, please check your paths.', fullfile(r.rfx_dir,r.conditions{i}));
    end
end
  
%---Loops through con files and get estimates
%--turn on spm_defaults
spm('Defaults','fmri');
start_time = datestr(now);   
fprintf('\n==========Extracting parameter estimates from ROIs at %s\n', start_time); 
%--Get the con images
conlist = cell(1,size(r.conditions,1));
con_vol = cell(1,size(r.conditions,1));
for i=1:size(r.conditions,1)
    fprintf('Loading contrast files for condition: %s\n',r.conditions{i});
    %Super regxp hack to get the proper con files, should never fail -DDW
    %fixed to make sure we never load the con_0002.img MARCH 2010DDW
    conlist{i} = spm_select('FPList',fullfile(r.rfx_dir,r.conditions{i}),'^con_.*_\d\d\d\d\.img'); 
    con_vol{i} = spm_vol(conlist{i});
end

%---Generate r.roi_specs from file or from user varible
if exist(r.spec_file,'file')
    fprintf('===ROI spec file found... Using ROI specs from file:%s...\n',spm_str_manip(r.spec_file,'t'));
    [num,txt,rawspecs] = xlsread(r.spec_file,'', '','basic');
    inew = 1;
    for ispecs = 2:size(rawspecs,1)
        %--check for nans since sometimes empty rows in excel still show up
        %--in xlsread.
        if ~isnan(rawspecs{ispecs,1})
            newspecs{inew,1} = rawspecs{ispecs,1};
            %check for nan since no cordinates for img files
            if sum(isnan(rawspecs{ispecs,2}))
                newspecs{inew,2} = '';
            else                
                newspecs{inew,2} = rawspecs{ispecs,2};
            end
            %check if not string since we expect strings (excel likes to
            %not always observe text formatting. 
            if isnumeric(rawspecs{ispecs,3})
                newspecs{inew,3} = num2str(rawspecs{ispecs,3});
            else
                newspecs{inew,3} = rawspecs{ispecs,3};
            end
            inew = inew + 1;
        end
        %--overwrite r.roi_specs with newspecs
        r.roi_specs = newspecs;
    end   
else
    fprintf('===No ROI spec file found... Using ROI specs from file:%s...\n',spm_str_manip(r.para_file,'t'));
end

%--Determine number of regions and con images
nsub    = size(conlist{1},1);
nclust  = size(r.roi_specs,1);
outdata = zeros(nsub,size(r.conditions,1));
%--Goto ROI folder
cd(r.roi)
%--Delete previous ROI files if exists
try delete('*.img'); end
try delete('*.hdr'); end
try delete('*.nii'); end

%---Loop through each cluster creating or loading ROI and extracting data
for iclust = 1:nclust 
    %--Figure out if img files or spherical ROI diameter
    if ~isempty(str2num(r.roi_specs{iclust,3}))
        %-Make spherical ROI
        fprintf('Making spherical ROI (%smm) for %s centered at:%s\n',...
            r.roi_specs{iclust,3},...
            r.roi_specs{iclust},...
            r.roi_specs{iclust,2});
        %-Here is temp code for the doughnut hack that sort of worked (i.e., punching a hole out of the ROI
        %-using a smaller ROI. I should revisit this sometime. Sept, 2012-DDW
        centersize = 0;
        sphere1    = make_sphere_mask([str2num(r.roi_specs{iclust,2})],str2num(r.roi_specs{iclust,3}),r.standard_space,r.roi_specs{iclust});
        if centersize == 0
            newmaskimg = sphere1.maskimg;
        else
            sphere2    = make_sphere_mask([str2num(r.roi_specs{iclust,2})],centersize,r.standard_space,r.roi_specs{iclust});
            newmaskimg = sphere1.maskimg - sphere2.maskimg;
        end  
        fprintf('Number of voxels in ROI: %d\n',numel(newmaskimg(newmaskimg==1)));
        sphere1.v.fname = sprintf('sphere_%s_%d_%d_%d.nii',r.roi_specs{iclust},str2num(r.roi_specs{iclust,2}));   
        spm_write_vol(sphere1.v,newmaskimg);     
        fname = sprintf('sphere_%s_%d_%d_%d.nii',r.roi_specs{iclust},str2num(r.roi_specs{iclust,2}));
        clust_vol(iclust) = spm_vol(spm_select('FPList',r.roi,fname));
    else
        %-Load img file
        fprintf('Loading ROI mask %s in %s\n',r.roi_specs{iclust,3},r.roi_img);
        clust_vol(iclust) = spm_vol(spm_select('FPList',r.roi_img,r.roi_specs{iclust,3}));
    end
    %--Read in the current ROI mask
    clust_data = spm_read_vols(clust_vol(iclust));
    roi        = find(clust_data);
    %--Loop through each subject
    fprintf('Extracting parameter estimates for subject:  ');
    for isub = 1:nsub      
        fprintf([repmat('\b',1,2),'%2.0f'],isub);
        %-Loop through each condition
        for icond = 1:size(r.conditions,1)
            con_data            = spm_read_vols(con_vol{icond}(isub));
            outdata(isub,icond) = nanmean(con_data(roi));
        end
    end
    fprintf('\n');
    %-Build ROI data structure
    %-Simple trick to eliminate the prefix and suffix from the con filenames
    subtmp = spm_str_manip(conlist{1},'tr');
    for isub = 1:size(subtmp,1)
        subnames{isub,1} = subtmp(isub,5:(length(deblank(subtmp(isub,:)))-5));
    end
    roidata(iclust) = struct(...
                            'Region',r.roi_specs{iclust},...
                            'ROImask',spm_str_manip(clust_vol(iclust).fname,'tr'),...
                            'Coords',r.roi_specs{iclust,2},... 
                            'Subject',{subnames},... 
                            'Data',outdata,... 
                            'Conditions',{r.conditions});
end
%--Drop me a new line bro!
fprintf('\n'); 
%thanks!

%---Print out ROI data in tab delimited
%--Delete previous file if exists
if exist(r.data_name,'file')
    delete(r.data_name); 
end
%--Loop through clusters
for currentcluster = 1:nclust
    fprintf('Saving data for %d subjects in region %s to file %s\n',nsub,roidata(currentcluster).Region, r.data_name);
    %-Open the file for writing
    fid = fopen(r.data_name,'a');
    if currentcluster == 1
        %Print the first column heading (region)
        fprintf(fid,'%s\t%s\t%s\t%s\t','Region','ROI mask','Coords','Subject');   
    %-Loop through all conditions, printing the column headers
        for ii = 1:length(roidata(currentcluster).Conditions)
            fprintf(fid,'%s\t',roidata(currentcluster).Conditions{ii}); 
        end
    end
    %-Loop through each subject to print name and data.
        for iii = 1:nsub
            fprintf(fid,'\n%s\t%s\t%s\t%s\t',...
                roidata(currentcluster).Region,...
                roidata(currentcluster).ROImask,...
                roidata(currentcluster).Coords,...
                roidata(currentcluster).Subject{iii});
            for iiii = 1:length(roidata(currentcluster).Conditions)
                fprintf(fid,'%6.3f\t',roidata(currentcluster).Data(iii,iiii));
            end
        end
    fclose(fid);
end
%---What did you do today?
fprintf('\nParameter estimate extraction finished.\nData saved to the file: %s',r.data_name);
fprintf('\nStored in the directory: %s\n\n',r.roi);
%---Give us a moment to digest.
pause(2);

%---Print out requested statistics to command window and file.
%---According to stats listed in r.roi_stats 
%---added jan 2010. 
%---Still working on it, now added anovas plus xls support. March 2013.
if ~isempty(r.roi_stats)
    %--Setup basic stats name
    [tmp1,tmp2,tmp3] = fileparts(r.data_name);
    diary_name       = [tmp2,'_stats',tmp3]; %string for diary name
    %--Open up xls file
    if exist(r.var_file,'file')
        fprintf('Loading variables file:%s...',spm_str_manip(r.var_file,'t'));
        [num,txt,xlsdata] = xlsread(r.var_file,'', '','basic');
        fprintf('Done\n');
        fprintf('Parsing variables file...\n');
        i_vars  = 1;
        for i_xls = 1:size(xlsdata,2)
            if strcmpi(xlsdata{1,i_xls},'subid')
                for i_row = 2:size(xlsdata,1)
                    xls_subjects{i_row-1,1} = xlsdata{i_row,i_xls};
                end
            elseif strcmpi(xlsdata{1,i_xls},'group')
                %Since we allow for string group IDs we got to parse this
                group_tmp = {};
                for i_row = 2:size(xlsdata,1)
                    group_tmp{i_row-1}   = xlsdata{i_row,i_xls};
                    xls_groupID{i_row-1,1} = xlsdata{i_row,i_xls};
                end
                group_uni = unique(group_tmp);
                %There has to be a better way to do this... 
                for i_row = 1:size(xls_groupID,1)
                   for i_id = 1:length(group_uni)
                       if strcmpi(xls_groupID{i_row},group_uni{i_id}) 
                            xls_group(i_row,1) = i_id;
                       end
                   end                    
                end
            else
                xls_ctitles{i_vars} = xlsdata{1,i_xls}; 
                for i_row = 2:size(xlsdata,1)
                    xls_cvars(i_row-1, i_vars) = xlsdata{i_row,i_xls};
                end
                i_vars = i_vars + 1;
            end           
        end
    end
    %--Delete previous file if exists
    if exist(diary_name,'file')
        delete(diary_name); 
    end
    diary(diary_name);
    fprintf(repmat('-',1,60));
    fprintf('\nBasic Statistics on data in %s\n',r.data_name);
    for i=1:length(roidata)
        fprintf(['===Region: %s(%s)\n'],roidata(i).Region,roidata(i).Coords);
        %-Store roi data into new variables with condition names.
        %-This is so that we can interpret formulas in r.roi_stats
        for i_con=1:length(roidata(i).Conditions)
            eval([roidata(i).Conditions{i_con},' = roidata(i).Data(:,i_con);']);
        end
        %-Now compute the desired statistics. This code might read better with
        %-more functions. But for now this works. 
        for i_stat=1:length(r.roi_stats)
            if strcmpi(r.roi_stats(i_stat),'descriptives')
                fprintf('===Descriptives\n');
            end
            for i_con=1:length(roidata(1).Conditions)
                %Check for magic word
                if strcmp(r.roi_stats{i_stat,2},'all_conditions')
                    evalthis = roidata(i).Conditions{i_con};
                else
                    evalthis = r.roi_stats{i_stat,2};
                end
                %Do Descriptives
                if strcmpi(r.roi_stats(i_stat),'descriptives')
                    %do descriptives on evalthis
                    fprintf('\tCondition: %s\n',evalthis);
                    fprintf('\tMean:%4.3f',eval(['mean(',evalthis,')']));
                    fprintf(' S.D.:%4.3f',eval(['std(',evalthis,')']));
                    fprintf(' MIN:%4.3f',eval(['min(',evalthis,')']));
                    fprintf(' MAX:%4.3f\n',eval(['max(',evalthis,')']));
                %Do T-TEST1
                elseif strcmpi(r.roi_stats(i_stat),'t-test1')
                    eval(['[h,p,ci,stats]=ttest(',evalthis,');'])
                    %Add sig stars
                    switch logical(true)
                    case p < 0.001
                        p_star = '***';
                    case p < 0.01
                        p_star = '**';                                                       
                    case p < 0.05
                        p_star = '*';
                    otherwise
                        p_star = '';
                    end 
                    fprintf('\t==t-test on Condition or Formula: %s\n',evalthis);
                    fprintf('\tt-test: t(%d)= %4.2f, p=%4.3f %s\n',stats.df,stats.tstat,p,p_star);
                %Do T-TEST2
                elseif strcmpi(r.roi_stats(i_stat),'t-test2')
                    %Do t-test2 on every possible pair of groups (if more than 2)
                    %Since groups depend on match to xls_group (and not
                    %just on xls_group). Determine matching now.
                    for i_subs = 1:size(roidata(1).Subject,1)
                        %find index of matching subject in xls data
                        subidx = find(strcmpi(xls_subjects,roidata(1).Subject{i_subs}));
                        if isempty(subidx)
                            error('Subject %s does not exist in %s...', condata{i_subs,2},r.var_file);
                        else
                            SubjectGroup(i_subs,1) = xls_group(subidx);
                        end
                    end                    
                    numGroups = length(unique(SubjectGroup));
                    comGroups = combntns(1:numGroups,2);
                    for i_grp = 1:size(comGroups,1)
                        %build up a cell array of data. 
                        condata      = num2cell(eval(evalthis));
                        condata(:,2) = roidata(i).Subject;
                        condata(:,3) = num2cell(SubjectGroup);
                        %Assign convals to group 1 and 2 based on group assignments
                        %and now we convert back from cell arrays. blimey.
                        group1 = cell2mat(condata(ismember(cell2mat(condata(:,3)),comGroups(i_grp,1)),1));
                        group2 = cell2mat(condata(ismember(cell2mat(condata(:,3)),comGroups(i_grp,2)),1));
                        [h,p,ci,stats]=ttest2(group1,group2);
                        %add sigstars to them pvalues
                        switch logical(true)
                        case p < 0.001
                            p_star = '***';
                        case p < 0.01
                            p_star = '**';                                                       
                        case p < 0.05
                            p_star = '*';
                        otherwise
                            p_star = '';
                        end
                        %print results 
                        %find groupID label
                        grp1_label = xls_groupID(find(xls_group == comGroups(i_grp,1)));
                        grp2_label = xls_groupID(find(xls_group == comGroups(i_grp,2)));
                        fprintf('\t==Independent t-test %s vs. %s for:%s\n',...
                            grp1_label{1},grp2_label{1},evalthis);
                        fprintf('\tGroup 1 %s: Mean:%4.3f',grp1_label{1}, mean(group1));
                        fprintf(' S.D.:%4.3f\n',std(group1));
                        fprintf('\tGroup 2 %s: Mean:%4.3f',grp2_label{1}, mean(group2));
                        fprintf(' S.D.:%4.3f\n',std(group2));
                        fprintf('\tIndependent t-test: t(%d)= %4.3f, p=%4.3f %s\n',stats.df,stats.tstat,p,p_star);
                    end                        
                %Do CORREL
                elseif strcmpi(r.roi_stats(i_stat),'correl')
                    %build up a cell array of data. 
                    condata      = num2cell(eval(evalthis));
                    condata(:,2) = roidata(i).Subject;
                    %now iterate and add corrvalues according to the xlsread data
                    for i_subs = 1:size(condata,1)
                        %find index of matching subject in xls data
                        subidx = find(strcmpi(xls_subjects,condata{i_subs,2}));
                        if isempty(subidx)
                            error('Subject %s does not exist in %s...', condata{i_subs,2},r.var_file);
                        else
                            for i_cors = 1:size(xls_cvars,2)
                                condata{i_subs,i_cors+2} = xls_cvars(subidx,i_cors);
                            end
                        end
                    end                    
                    %loop through lenght of r.roi_corr
                    for corr_i = 3:size(condata,2)
                        %do correlations
                        [rcorr,p] = corrcoef(cell2mat(condata(:,1)),cell2mat(condata(:,corr_i)));     
                        %grab only the corr we need
                        rcorr=rcorr(1,2);
                        p=p(1,2);
                        %add sigstars to them pvalues
                        switch logical(true)
                        case p < 0.001
                            p_star = '***';
                        case p < 0.01
                            p_star = '**';                                                       
                        case p < 0.05
                            p_star = '*';
                        otherwise
                            p_star = '';
                        end
                        %print results 
                        fprintf('\t==Correlation (Var: %s) on Condition: %s\n',xls_ctitles{corr_i-2}, evalthis);
                        fprintf('\tCorrelation: r=%4.2f, p=%4.3f %s\n',rcorr,p,p_star);                                                     
                    end
                else
                    fprintf('Invalid stat... Basic statistics recognizes only descriptives, t-test1, t-test2 and correl\n');                                       
                end
                if ~strcmpi(r.roi_stats{i_stat,2},'all_conditions')
                    break;
                end
            end
        end
    fprintf(repmat('-',1,60));
    fprintf('\n');   
    end
    diary off;
    fprintf('\nBasic stats output has been saved to the file %s',diary_name);
    fprintf('\nStored in the directory: %s\n',r.roi);
end
%---Go home you slag!
cd(r.root);       

%---ADDITIONAL FUNCTIONS
function sphere=make_sphere_mask(loc,radius,img,region)
% Creates a mask containing a single sphere
% usage: make_sphere_mask([-21 -24 0],8) creates a sphere with 8 mm radius
% centered at MNI coordinates [-21 -24 0]
% MODIFICATIONS:
% -Voxels are now rounded to nearest location gridspace and user is warned.
%  This helps catch errors but also allows for users to input coordinates
%  that are not on the native gridspace (e.g. peaks from other studies).
%  DDW June 2008
% -Removes some flipping fixes that were uncessary and causing crashing on 
%  dartmouth data (our philips data isn't flipped... I think... I hope).
%  DDW June 2008
% -Modified and added as part of spm8w_getdata.m (since we never use it
%  outside of this context. Makes for cleaner files.). Also added some
%  info to the volume description field -DDW Jan 2010

%---Load standard_space.img
v=spm_vol(img); %Fixed for spm8, spm_vol in spm8 requires explicit path.
  
%---Round input voxels to gridspace. This should work as long as the gridspace is isotropic.
loc_original=loc;
%--divide location by voxel size from v.mat and round and correct
loc=round(loc/abs(v.mat(1,1)))*abs(v.mat(1,1)); 
if (loc_original(1)==loc(1))==0 || (loc_original(2)==loc(2))==0 || (loc_original(3)==loc(3))==0
    fprintf('Warning coordinates have been rounded to nearest voxel in image space\n');
    fprintf('coordinates %s have been rounded to %s \n',num2str(loc_original),num2str(loc));
end
    
%---Find the voxel that is nearest on the grid
x=[v.mat(1,4):v.mat(1,1):v.dim(1)*v.mat(1,1)];
y=[v.mat(2,4):v.mat(2,2):v.dim(2)*v.mat(2,2)];
z=[v.mat(3,4):v.mat(3,3):v.dim(3)*v.mat(3,3)];

%---Check that it's on grid. Our default bounding box from spm2 caused a
%---massive fail in SPM8 here due to allowing non integers as origins
%---causing a rounding problem and grid getting shfited in y direction.
%---BLOOOOOOOOODY NIGHTMARE TO FIX!!!!! ended up making small adjustment 
%---to bounding box (see spm_preprocess under normalise section). All good
%---now... -Jan 2010 DDW
if isempty(find(x==loc(1))) | isempty(find(y==loc(2))) | isempty(find(z==loc(3))),
    error('the specified location is not on the grid!');
end;

%---Fix any transpose issues.
if size(loc,1)<size(loc,2)
    loc=loc';
end;
    
%----------------Have to turn this back on for SPM8 data
%----------------It's off for SPM2 data (no negative x in spm2)
%---- fix for flipped images (where x dim = negative)
%---- jm 05/10/07
if v.mat(1,1)<0
   v.mat(1,1)=v.mat(1,1)* -1;
end
 
%---create a list of possible coordinates
xfudge=round(2*radius/v.mat(1,1))*v.mat(1,1);
yfudge=round(2*radius/v.mat(2,2))*v.mat(2,2);
zfudge=round(2*radius/v.mat(3,3))*v.mat(3,3);
XYZmm=[];
c=1;

for x=loc(1)-xfudge:v.mat(1,1):loc(1)+xfudge;
    for y=loc(2)-yfudge:v.mat(2,2):loc(2)+yfudge;
        for z=loc(3)-zfudge:v.mat(3,3):loc(3)+zfudge;
        %fprintf('%d\t%d\t%d\n',x,y,z);
        XYZmm(:,c)=[x;y;z];
        c=c+1;
        end;
    end;
end;

j  = find(sum((XYZmm - loc*ones(1,size(XYZmm,2))).^2) <= radius^2);  
maskimg=zeros(v.dim(1:3));
  
%----------------Have to turn this back on for SPM8 data
%----------------It's off for SPM2 data (no negative x in spm2)
%--- reflip x co-ordinate jm 05/10/07
v.mat(1,1)=v.mat(1,1)*-1;
%----------------
  
for i=j,
    coord=[];
    coord(1)=(XYZmm(1,i)-v.mat(1,4))/v.mat(1,1);
    coord(2)=(XYZmm(2,i)-v.mat(2,4))/v.mat(2,2);
    coord(3)=(XYZmm(3,i)-v.mat(3,4))/v.mat(3,3);
    maskimg(coord(1),coord(2),coord(3))=1;
end;
  
sphere=struct('j',j,'v',v,'maskimg',maskimg);

%Temphack for center supress - DDW 2012/Sept
%%% Fix the name and descriptions
% v.fname=sprintf('sphere_%s_%d_%d_%d.img',region,loc_original);
% v.descrip=sprintf('%dmm ROI mask at region %s and coordinates %d %d %d',radius,region, loc);
% spm_write_vol(v,maskimg);
return