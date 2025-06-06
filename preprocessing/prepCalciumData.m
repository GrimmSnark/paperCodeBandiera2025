function prepRetinaCalcium(filePath, motionCorrFlag, motionCorrectionType, createDFPixelMovieFlag, zeroDFStack, channelOrg)
% This function does basic preprocessing of t series imaging data including
% meta data, image registration,  creates dF_F pixelwise movie and summary
% SD images from .nd2 files from FLAME system
%
% Written by Michael Savage (michael.savage2@ncl.ac.uk)
%
% Input- filePath: image data .nd2 file from FLAME system
%
%        motionCorrFlag- Flag do motion correction on raw images
%
%        motionCorrectionType - DFT-based subpixel method
%                               ('subMicronMethod')
%                             - non-rigid NoRM Corr registration
%                               ('nonRigid')
%
%        createDFPixelMovieFlag: flag for creating pixel wise DF_F stack
%        and takes up time/space 0 = not saved, 1 = saved (DEFAULT)
%
%        zeroDFStack - 0/1 to make and negative DF signal zero for the DF
%                      movies DEFAULT = 1
%
%        channelOrg - two element vector showing organisation of calcium 
%                     then blood vessel channels, first element is the
%                     calcium channel no, the second is the blood vessel
%                     channel DEFAULT [1 2]
%                     

%% defaults

if nargin < 1 || isempty(filePath)
    [file, path] = uigetfile({'*.nd2;*.tif;*.tiff;*.czi'},...
        'Image File Selector');

    filePath = fullfile(path,file);
end

if nargin < 2 || isempty(motionCorrFlag)
    motionCorrFlag = 1;
end

if nargin < 3 || isempty(motionCorrectionType)
    motionCorrectionType = 'subMicronMethod';
end


if nargin < 4 || isempty(createDFPixelMovieFlag)
    createDFPixelMovieFlag = 1;
end

if nargin < 5 || isempty(zeroDFStack)
    zeroDFStack = 1;
end

if nargin <6 || isempty(channelOrg)

    calciumChan = 1;
    bvChan = 2;
else
    calciumChan = channelOrg(1);
    bvChan = channelOrg(2);
end

noOfImagesForAlignment = 100; % number of brightest images used for motion correction template image

%% get save folder locations
[folderParts, name, ext ] = fileparts(filePath);

%% read in image file
if strcmp(ext, '.nd2')  || strcmp(ext, '.czi')
%     profile on
    [imStack, metaData] = readFLAMEData(filePath);

%     profile viewer
    % split into channels
    imStack = reshape(imStack, size(imStack,1), size(imStack,1), length(metaData.colours.emWavelength), []);
    imStackCal = squeeze(imStack(:,:,calciumChan,:));

    imStackBV = [];
    if size(imStack,3) > 1
        % take single slice from blood vessel channel
        if gpuDevice > 0
            imStackBV = gpuArray(squeeze(imStack(:,:,bvChan,:)));
        else
            imStackBV = squeeze(imStack(:,:,bvChan,:));
        end
    end

    %clean up to save space
    clear('imStack');

    if ~isempty(imStackBV)
        if gpuDevice > 0
            ImBV = stdGPU(imStackBV,3);
            imageIMSD = uint16(mat2gray(ImBV) * 65535);
            saveastiff(gather(imageIMSD), fullfile(folderParts, [name '_BV_SD.tif']));
        else
            ImBV = stdGPU(imStackBV,3);
            imageIMSD = uint16(mat2gray(ImBV) * 65535);
            saveastiff(imageIMSD, fullfile(folderParts, [name '_BV_SD.tif']));
        end

            %clean up to save space
            clear('imStackBV');
    end

else
    imStackCal = read_Tiffs(filePath);
    metaData = [];
    metaData.filePath = filePath;
    metaData.rate = 10;
    metaData.image.pixelNum = size(imStackCal, 1);
    metaData.image.pixelSize = 0.41;
end


%% motion correction

if motionCorrFlag == 1
    % we want to use the brightness average
    % get image brightness in stack
    imageBrightness = squeeze(mean(imStackCal,[1,2]));

    % sort image brightness
    [~, imageBrightnessIndx] = sort(imageBrightness);
    % make average image based on noOfImages brightest images
    templateImageForReg = uint16(mean(imStackCal(:,:,imageBrightnessIndx(1:noOfImagesForAlignment-1)),3));

    disp(['Starting image registration using ' motionCorrectionType ]);
    [imStackCal,xyShifts, options_nonrigid] = imageRegistration(imStackCal,motionCorrectionType, metaData.image.pixelSize, [], templateImageForReg);
    metaData.xyShifts = xyShifts;
    metaData.options_nonrigid = options_nonrigid;
else
    metaData.xyShifts = [];
    metaData.options_nonrigid = [];
end

%% create DF/F image stack

if createDFPixelMovieFlag == 1
    [dFStack, metaData] = createDFPixelImageStack(imStackCal, metaData);

    % zero out the minus values if flag
    if zeroDFStack
        dFStack(dFStack < 0) = 0;
    end

    % save dF image
    saveastiff(dFStack, fullfile(folderParts, [name '_dF_F.tif']));

    % create SD of DF movie
    imageDF_SD = std(double(dFStack),[],3);
    imageDF_SD = uint16(mat2gray(imageDF_SD) * 65535);
    saveastiff(imageDF_SD, fullfile(folderParts, [name '_dF_SD.tif']));
end
%% save meta and SD image

save(fullfile(folderParts, [name '_ExStruct.mat']), 'metaData', '-v7.3');

% clean up a little
clear metaData


if gpuDeviceCount == 1 % tries for GPU  version, which will only work if nvidia CUDA installed
    imageSD = stdGPU(imStackCal);
else
    imageSD = std(double(imStackCal),[],3);
end

imageSD = uint16(mat2gray(imageSD) * 65535);
saveastiff(imageSD, fullfile(folderParts, [name '_SD.tif']));

end