clear; close all; clc;

% ====================user's modify start=====================
outputFolder = "/media/ourDataset/preprocess/20211028_1/TIRadar";
if ~exist(outputFolder, "dir")
    fprintf("Create outputfolder: %s\n", outputFolder);
    mkdir(outputFolder);
end

dayFolder = "/mnt/DATASET/20211028_1/TIRadar";
groupFolders = dir(dayFolder);

calibFileName = "./input/256x64.mat";
pathGenParaFolder = 'input';
PARAM_FILE_GEN_ON = 0;
rangeFFTFilter_ON = 1;
dopplerFFTFilter_ON = 1;
WAITKEY_ON = 0;
CHECK_LOG_ON = 0;
PLOT_ON = 0;
SAVE_ON = 1;
% ====================user's modify end=====================


%% create mmwave.json parameters file
if PARAM_FILE_GEN_ON == 1
    radarFolder = fullfile(dayFolder, groupFolders(3).name);
    radarInfoFile = dir(fullfile(radarFolder, '*.mmwave.json'));
    parameter_files_path = parameter_file_gen_json(fullfile(radarInfoFile.folder, radarInfoFile.name), calibFileName, pathGenParaFolder);   
end


parfor groupFolderIndex = 3:length(groupFolders)    

    radarFolder = fullfile(dayFolder, groupFolders(groupFolderIndex).name);
    if length(dir(radarFolder)) ~= 37
        fprintf('%s the number of files is not right.\n', radarFolder)
        continue;
    end

    radarTimeFile = dir(fullfile(radarFolder, '*.startTime.txt'));
    radarInfoFile = dir(fullfile(radarFolder, '*.mmwave.json'));
    radarBinFile_list = dir(fullfile(radarFolder, '*.bin'));

    parameter_files_path = struct();
    parameter_files_path(1).path = fullfile('input','subFrame0_param.m');
    parameter_files_path(2).path = fullfile('input','subFrame1_param.m');
    
    %% radar data check
    % get sliceId based path
    sliceIdBasedPath = getSliceIdBasedPath(radarBinFile_list);
    
    % initialization
    subFramesInfo = struct();
    cnt_globalSubFrames = 0;
    cnt_globalFrames = 0;
    
    % get parameter from 
    totNumFrames = getPara(parameter_files_path(1).path, 'frameCount');
    NumSubFramesPerFrame = getPara(parameter_files_path(1).path, 'NumSubFrames');
    totNumSubFrames = totNumFrames * NumSubFramesPerFrame;
    
    for sliceId = 1:length(sliceIdBasedPath)
        num_validSubFrames = getValidFrames(sliceIdBasedPath, sliceId);
        num_validFrames = num_validSubFrames / NumSubFramesPerFrame;
        for frameId = 0: num_validFrames-1  
            cnt_globalFrames = cnt_globalFrames +1;
            if CHECK_LOG_ON
                disp('===========================================================');
                fprintf('??????????????? %s ????????? %d/%d ?????????????????? %d/%d ??????\n',  sliceIdBasedPath(sliceId).sliceId, frameId, num_validFrames-1, cnt_globalFrames-1, totNumFrames);
            end
            
            for i_subFrame = 0 : NumSubFramesPerFrame -1
                cnt_globalSubFrames = cnt_globalSubFrames + 1;
                subFrameId = i_subFrame + frameId * NumSubFramesPerFrame;
                if CHECK_LOG_ON
                    fprintf('??????????????? %d/%d ????????????????????? %d/%d ???????????????\n',  subFrameId, num_validSubFrames-1, cnt_globalSubFrames-1, totNumSubFrames);
                end
                
                % record frame information
                subFramesInfo(cnt_globalSubFrames).globalSubFrameId = cnt_globalSubFrames-1;
                curSubFrameInfo = getFrameInfo(sliceIdBasedPath, sliceId, subFrameId);
                fieldnames_cell = fieldnames(curSubFrameInfo);
%                 for i_field = 1: length(fieldnames_cell)
%                     fieldname = fieldnames_cell{i_field};
%                     eval(['subFramesInfo(cnt_globalSubFrames).', fieldname, ' = curSubFrameInfo.', fieldname, ';\n']);            
%                 end
                subFramesInfo(cnt_globalSubFrames).sliceFrameId = curSubFrameInfo.sliceFrameId;
                subFramesInfo(cnt_globalSubFrames).master_adcDataPath = curSubFrameInfo.master_adcDataPath;
                subFramesInfo(cnt_globalSubFrames).master_timestamp = curSubFrameInfo.master_timestamp;
                subFramesInfo(cnt_globalSubFrames).master_offset = curSubFrameInfo.master_offset;
                subFramesInfo(cnt_globalSubFrames).slave1_adcDataPath = curSubFrameInfo.slave1_adcDataPath;
                subFramesInfo(cnt_globalSubFrames).slave1_timestamp = curSubFrameInfo.slave1_timestamp;
                subFramesInfo(cnt_globalSubFrames).slave1_offset = curSubFrameInfo.slave1_offset;
                subFramesInfo(cnt_globalSubFrames).slave2_adcDataPath = curSubFrameInfo.slave2_adcDataPath;
                subFramesInfo(cnt_globalSubFrames).slave2_timestamp = curSubFrameInfo.slave2_timestamp;
                subFramesInfo(cnt_globalSubFrames).slave2_offset = curSubFrameInfo.slave2_offset;
                subFramesInfo(cnt_globalSubFrames).slave3_adcDataPath = curSubFrameInfo.slave3_adcDataPath;
                subFramesInfo(cnt_globalSubFrames).slave3_timestamp = curSubFrameInfo.slave3_timestamp;
                subFramesInfo(cnt_globalSubFrames).slave3_offset = curSubFrameInfo.slave3_offset;


            end
            
        end
        
    end
    
    % check if drop some subframes?
    subFrame_timeDiff = subFramesInfo(2).master_timestamp - subFramesInfo(1).master_timestamp;
    timeDiff_permitError = 1000;% us
    if (subFrame_timeDiff - getPara(parameter_files_path(1).path, 'SubFramePeriod') * 1000) > timeDiff_permitError
        dropSubframe = true;
        fprintf('===========================================================\n(%s)## WARNING: ???????????????????????????????????????\n', radarFolder);
    else
        dropSubframe = false;
    end
    
    
    %% get pcStartTime & radarStartTime and calculate difference between pcStartTime and radarStartTime
    pcStartTime = getPCStartTime(radarTimeFile);
    radarStartTime = getRadarStartTime(fullfile(radarFolder, 'master_0000_idx.bin'));
    if dropSubframe
        radarStartTime = radarStartTime - 15000;
    end
    timestamp_diff = pcStartTime - radarStartTime;
    
    %% radar process
    if dropSubframe
        i_globalSubFrame = 1;
    else
        i_globalSubFrame = 0;
    end
    
    cnt_frame_processed = 0;
    
    while (i_globalSubFrame+1 < cnt_globalSubFrames)        

        cnt_frame_processed = cnt_frame_processed + 1;
        
        % ??????????????????
        timestamp_radar = subFramesInfo(i_globalSubFrame+1).master_timestamp + timestamp_diff;
        fprintf('???????????????%.6f s\n', double(timestamp_radar)/1e6);
    
        % check the current frame has been generated?
        if SAVE_ON
            pcd_path = fullfile(outputFolder, strcat(sprintf('%.3f', round(double(timestamp_radar)/1e6, 3)), ".pcd"));
            heatmap_path = fullfile(outputFolder, strcat(sprintf('%.3f', round(double(timestamp_radar)/1e6, 3)), ".heatmap.bin"));
            if exist(pcd_path, "file") && exist(heatmap_path, "file")
                fprintf("%s already has been generated.\n", pcd_path);
                fprintf("%s already has been generated.\n", heatmap_path);
                i_globalSubFrame = i_globalSubFrame +NumSubFramesPerFrame;
                continue;
            end
        end
        
        % ??????adc??????
        % read raw data
        adcDatas = readAdcData(subFramesInfo, i_globalSubFrame, parameter_files_path);
        % calibrate raw data
        adcDatas = calibAdcData(adcDatas, calibFileName, parameter_files_path);
        
        % ??????????????????????????????
        subFrame_results = struct();
        % ???????????????
        for i_subFrame = 0 : NumSubFramesPerFrame - 1
            fprintf('>>??????????????? %d ??????       ',  i_subFrame);
            adcData = adcDatas(i_subFrame + 1).adcData;
            % reorder 
            RxForMIMOProcess = getPara(parameter_files_path(i_subFrame + 1).path, 'RxForMIMOProcess');
            adcData = adcData(:,:,RxForMIMOProcess,:);
    
            % rangeFFT
            tic;
            rangeFFTOut = rangeFFT(adcData, parameter_files_path(i_subFrame + 1).path, rangeFFTFilter_ON);
            fprintf('rangeFFT??????%.3f s       ', toc);
    
            % dopplerFFT
            tic;
            dopplerFFTOut = dopplerFFT(rangeFFTOut, parameter_files_path(i_subFrame + 1).path, dopplerFFTFilter_ON);
            fprintf('dopplerFFT??????%.3f s       ', toc);
    
            % ?????????????????????????????????????????????Chirp??????????????????????????????????????????chirp??????????????????????????? ???
            dopplerFFTOut = reshape(dopplerFFTOut,size(dopplerFFTOut,1), size(dopplerFFTOut,2), size(dopplerFFTOut,3)*size(dopplerFFTOut,4));
            % ????????????????????????
            sig_integrate = 10*log10(sum((abs(dopplerFFTOut)).^2,3) + 1);
            subFrame_results(i_subFrame + 1).dopplerMap = sig_integrate;
            
    
            % CFAR
            tic;
            detection_results = CFAR(dopplerFFTOut, parameter_files_path(i_subFrame + 1).path);
            fprintf('CFAR??????%.3f s       ', toc);
            detect_all_points = zeros(length(detection_results), 3);%?????????CFAR????????????????????????
            for iobj = 1 : length(detection_results)
                detect_all_points (iobj,1)=detection_results(iobj).rangeInd+1;%range index
                detect_all_points (iobj,2)=detection_results(iobj).dopplerInd_org+1;%doppler index
                detect_all_points (iobj,3)=detection_results(iobj).estSNR;%estimated SNR
            end
            subFrame_results(i_subFrame + 1).CFARResults = detection_results;
            
            
            % DOA
            if ~isempty(detection_results)
                tic;
                angleEst = DOA(detection_results, parameter_files_path(i_subFrame + 1).path);
                fprintf('DOA??????%.3f s\n', toc);
                
                if ~isempty(angleEst)%???????????????????????????
                    angles_all_points = zeros(length(angleEst), 6);%?????????DOA????????????????????????
                    xyz = zeros(length(angleEst), 9);%?????????DOA???????????????????????????????????????????????????
                    for iobj = 1:length(angleEst)%??????iobj???????????????
                        % angleEst.angles???4?????????????????????????????????????????????azimuth????????????????????????elvation
                        angles_all_points (iobj,1)=angleEst(iobj).angles(1);%?????????azimuth                    
                        % ??????z?????????????????????????????????????????????elevation??????????????????????????????20210531??????
                        angles_all_points (iobj,2)=-angleEst(iobj).angles(2);%?????????elvation                    
                        angles_all_points (iobj,3)=angleEst(iobj).estSNR;%???????????????
                        angles_all_points (iobj,4)=angleEst(iobj).rangeInd;%???range???Index
                        angles_all_points (iobj,5)=angleEst(iobj).doppler_corr;%???doppler_corr
                        angles_all_points (iobj,6)=angleEst(iobj).range;%???range
    
                        xyz(iobj,1) = angles_all_points (iobj,6)*sind(angles_all_points (iobj,1))*cosd(angles_all_points (iobj,2));%x
                        xyz(iobj,2) = angles_all_points (iobj,6)*cosd(angles_all_points (iobj,1))*cosd(angles_all_points (iobj,2));%y
                        xyz(iobj,3) = angles_all_points (iobj,6)*sind(angles_all_points (iobj,2));%z
                        xyz(iobj,4) = angleEst(iobj).doppler_corr;%v
                        xyz(iobj,5) = angleEst(iobj).range;%range
                        xyz(iobj,6) = angleEst(iobj).estSNR;%??????????????????
                        xyz(iobj,7) = angleEst(iobj).doppler_corr_overlap;%???doppler_corr_overlap
                        xyz(iobj,8) = angleEst(iobj).doppler_corr_FFT;%???doppler_corr_FFT
                        xyz(iobj,9) = angleEst(iobj).dopplerInd_org;%???dopplerInd_org
                    end
                end
            end
            subFrame_results(i_subFrame + 1).DOAResults = angleEst;
            subFrame_results(i_subFrame + 1).xyz = xyz;
    
            % heatmap
            range_resolution = getPara(parameter_files_path(i_subFrame + 1).path, 'rangeBinSize');
            TDM_MIMO_numTX = size(adcData,4);
            numRxAnt = size(adcData,3);
            antenna_azimuthonly = getPara(parameter_files_path(i_subFrame+1).path, 'antenna_azimuthonly');
            mode = 'dynamic';%mode: 'static'/'dynamic'/'static+dynamic'
            minRangeBinKeep =  5;
            rightRangeBinDiscard =  20;
            heatmap = struct();
            [heatmap.mag_data_static, heatmap.mag_data_dynamic, heatmap.y_axis, heatmap.x_axis] = plot_range_azimuth_2D(range_resolution, dopplerFFTOut,TDM_MIMO_numTX,numRxAnt,...
                antenna_azimuthonly, 0, mode, 0, minRangeBinKeep,  rightRangeBinDiscard);        
            subFrame_results(i_subFrame + 1).heatmap = heatmap;
            
            
            
            if PLOT_ON
                row_totFigure = 4;
                cnt_rowFigure = 0;
                
                figure(1);
                if i_subFrame == 0
                    clf;
                end
                % ????????????
                position_left = [0, 0.3, 0.65, 0.65, 0, 0.3, 0.65, 0.65];
                position_bottom = [0.5, 0.5, 0.5, 0.75, 0, 0, 0, 0.25];
                position_width = [0.27, 0.27, 0.281, 0.281, 0.27, 0.27, 0.281, 0.281];
                position_height = [0.48, 0.48, 0.25, 0.25, 0.48, 0.48, 0.25, 0.25];
                
                rangeBin_list = ( 1 : getPara(parameter_files_path(i_subFrame + 1).path, 'rangeFFTSize') ) * getPara(parameter_files_path(i_subFrame + 1).path, 'rangeBinSize');
                velocityBin_list = ( -1*getPara(parameter_files_path(i_subFrame + 1).path, 'DopplerFFTSize')/2 : getPara(parameter_files_path(i_subFrame + 1).path, 'DopplerFFTSize')/2-1 ) * getPara(parameter_files_path(i_subFrame + 1).path, 'velocityBinSize');
                subFrame_results(i_subFrame + 1).rangeBin_list = rangeBin_list;
                subFrame_results(i_subFrame + 1).velocityBin_list = velocityBin_list;
                
                
                % ?????????Doppler Map?????????
                % ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????0???????????????CFAR????????????
                cnt_rowFigure = cnt_rowFigure + 1;
                figId = i_subFrame*row_totFigure+cnt_rowFigure;
                ax = axes('OuterPosition', [position_left(figId), position_bottom(figId), position_width(figId), position_height(figId)], 'Box', 'on');
                plot(ax, rangeBin_list, sig_integrate(:, size(sig_integrate,2)/2+1), 'g', 'LineWidth', 4);
                hold on;
                for vId=1 : size(sig_integrate, 2)
                    powerList_vvId = sig_integrate(:,vId);
                    plot(rangeBin_list, powerList_vvId);
                    % ??????CFAR????????????
                    if ~isempty(detection_results)%????????????CFAR????????????????????????
                        ind = find(detect_all_points(:,2)==vId);%????????????Doppler??????????????????????????????
                        if (~isempty(ind))%??????????????????
                            rangeInd = detect_all_points(ind,1);%?????????????????????range index
                            plot(ax, rangeBin_list(rangeInd), sig_integrate(rangeInd, vId),...
                                'o',...
                                'LineWidth', 2,...
                                'MarkerEdgeColor', 'k',...
                                'MarkerFaceColor', [.49 1 .63],...
                                'MarkerSize', 6);
                        end
                    end
                end
                grid on;
                xlabel('Range(m)');
                ylabel('Receive Power (dB)');
                title(' DopplerMap I');
                hold off;
                set(ax, 'xLim', [0, rangeBin_list(end)]);
                
                % ?????????Doppler Map
                % ?????????????????????????????????????????????
                cnt_rowFigure = cnt_rowFigure + 1;
                figId = i_subFrame*row_totFigure+cnt_rowFigure;
                ax = axes('OuterPosition', [position_left(figId), position_bottom(figId), position_width(figId), position_height(figId)], 'Box', 'on');
                imagesc(ax, velocityBin_list, rangeBin_list, sig_integrate);
                c = colorbar;
                c.Label.String = 'Relative Power(dB)';
                xlabel('Velocity(m/s)   -: close to, +: away');
                ylabel('Range(m)');
                title(' DopplerMap II');            
                
                % ??????????????????
                cnt_rowFigure = cnt_rowFigure + 1;
                figId = i_subFrame*row_totFigure+cnt_rowFigure;
                ax = axes('OuterPosition', [position_left(figId), position_bottom(figId), position_width(figId), position_height(figId)], 'Box', 'on');
                scatter3(ax, xyz(:, 1), xyz(:, 2), xyz(:, 3), 10, (xyz(:, 4)),'filled');%x,y,z,v
                c = colorbar;
                c.Label.String = 'velocity (m/s)'; 
                set(ax, 'CLim', [velocityBin_list(1), velocityBin_list(end)]);
                grid on;
                xlabel('X (m)');
                ylabel('Y (m)');
                zlabel('Z (m)');
                colormap('jet');                              
                title(sprintf('???????????????%.6f s', double(subFramesInfo(i_globalSubFrame + i_subFrame + 1).master_timestamp + timestamp_diff)/1e6));
                hold on;
                xyz_zero = xyz(xyz(:,4)==0, :);
                scatter3(ax, xyz_zero(:,1), xyz_zero(:,2), xyz_zero(:,3), 10, (xyz_zero(:,4)),'w', 'filled');
                hold off;
                axis(ax, 'equal');
                set(ax, 'Color', [0.8,0.8,0.8]);
                set(ax, 'xLim', [-rangeBin_list(end), rangeBin_list(end)]);
                set(ax, 'yLim', [0, rangeBin_list(end)]);
                view([0, 90]);    
                
                % ??????????????????
                cnt_rowFigure = cnt_rowFigure + 1;
                figId = i_subFrame*row_totFigure+cnt_rowFigure;
                ax = axes('OuterPosition', [position_left(figId), position_bottom(figId), position_width(figId), position_height(figId)], 'Box', 'on');
                surf(subFrame_results(i_subFrame + 1).heatmap.y_axis,...
                    subFrame_results(i_subFrame + 1).heatmap.x_axis,...
                    (subFrame_results(i_subFrame + 1).heatmap.mag_data_dynamic).^0.1,'EdgeColor','none');
                view(2);
                xlabel('meters');
                ylabel('meters');
    
            end        
        end
        if PLOT_ON
            pause(0.1);
        end 
        
        if SAVE_ON
            xyz_save = [];
            v_save = [];
            snr_save = [];        
            
            for iSave = 0 : NumSubFramesPerFrame - 1
                xyz_save = [xyz_save; subFrame_results(iSave+1).xyz(:, 1:3)];
                v_save = [v_save; subFrame_results(iSave+1).xyz(:, 4)];
                snr_save = [snr_save; subFrame_results(iSave+1).xyz(:, 6)];
            end
            frame_dara = [xyz_save, v_save, snr_save];        
            pcd_path = fullfile(outputFolder, strcat(sprintf('%.3f', round(double(timestamp_radar)/1e6, 3)), ".pcd"));
            writepcd(pcd_path, frame_dara);
    
            % bin_save = [];
            
            heatmap = struct();
            heatmap.heatmap_static = subFrame_results(1).heatmap.mag_data_static;
            heatmap.heatmap_dynamic = subFrame_results(1).heatmap.mag_data_dynamic;
            heatmap.heatmap_xBin_list = subFrame_results(1).heatmap.y_axis;
            heatmap.heatmap_yBin_list = subFrame_results(1).heatmap.x_axis;
            heatmap_path = fullfile(outputFolder, strcat(sprintf('%.3f', round(double(timestamp_radar)/1e6, 3)), ".heatmap.bin"));
            heatmap_save(heatmap_path, heatmap);
            
        end   
        
        %% ????????????????????????NumSubFramesPerFrame?????????
        i_globalSubFrame = i_globalSubFrame +NumSubFramesPerFrame;
        
        if WAITKEY_ON
            key = waitforbuttonpress;
                while(key==0)
                    key = waitforbuttonpress;
                end        
        end
    end

end


function heatmap_save(heatmap_path, heatmap)
    temp = [heatmap.heatmap_static; heatmap.heatmap_dynamic; heatmap.heatmap_xBin_list; heatmap.heatmap_yBin_list];
%     tic;
    fileID = fopen(heatmap_path,'w');
    fwrite(fileID, temp,'float');
    fclose(fileID);
%     toc;

%     fileID = fopen(heatmap_path,'r');
%     temp2 = fread(fileID,[1028, 232],'float');
%     fclose(fileID);
end


function writepcd(output_pcd_path, pcd_data)
    fid = fopen(output_pcd_path, "w");
    fprintf(fid, "VERSION .7\n" + ...
        "FIELDS x y z velocity SNR\n" + ...
        "SIZE 4 4 4 4 4\n" + ...
        "TYPE F F F F F\n" + ...
        "COUNT 1 1 1 1 1\n" + ...
        "WIDTH %d\n" + ...
        "HEIGHT 1\n" + ...
        "VIEWPOINT 0 0 0 1 0 0 0\n" + ...
        "POINTS %d\n" + ...
        "DATA ascii\n", size(pcd_data, 1), size(pcd_data, 1));
    fclose(fid);
    writematrix(pcd_data, output_pcd_path, "FileType", "text", "WriteMode", "append","Delimiter", " ");
end