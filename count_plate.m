clc; clear; close all;

% Define the folder path for images and output folder for Excel
folderPath = 'X:\XXXX\XXXX\FOLDER_NAME';
outputFolderPath = 'X:\XXXX\XXXX\FOLDER_NAME';

% Create output folder if it does not exist
if ~exist(outputFolderPath, 'dir')
    mkdir(outputFolderPath);
end

% Get a list of all image files in the folder (e.g., JPG, PNG, BMP)
imageFiles = dir(fullfile(folderPath, '.JPG')); % Change extension if needed

% Check if images exist in the folder
if isempty(imageFiles)
    error('No image files found in the folder.');
end

% Initialize a cell array to store the results (filename and colonies count)
results = {};

for i = 1:length(imageFiles)
    % Read the image from the folder
    imgPath = fullfile(folderPath, imageFiles(i).name);
    img = imread(imgPath);

    if size(img, 3) == 3
        img = rgb2gray(img);
    end

    % Binarize and fill holes
    Mask = imbinarize(img);
    Mask = imfill(Mask, "holes");
    Mask = bwareaopen(Mask, 3000);

    % ค้นหารัศมีของวงกลม
    SstatsS = regionprops(Mask, 'Centroid', 'EquivDiameter');
    if isempty(SstatsS)
        disp(['Skipping ', imageFiles(i).name, ' (no valid circular region detected)']);
        continue;
    end
    [~, idx] = max([SstatsS.EquivDiameter]);
    center = SstatsS(idx).Centroid;
    radius = SstatsS(idx).EquivDiameter / 2;

    % สร้างหน้ากากที่ครอบคลุม 90% ของรัศมี
    [rows, cols] = size(Mask);
    [X, Y] = meshgrid(1:cols, 1:rows);
    mask = ((X - center(1)).^2 + (Y - center(2)).^2) <= ((0.90 radius)^2);

    % ใช้หน้ากากเพื่อลบขอบออก 10%
    bw_trimmed = Mask & mask;

    maskedImg = img;
    maskedImg(~bw_trimmed) = 0;
    % 🔹 กรองสัญญาณรบกวน
    Kmedian = medfilt2(maskedImg);
    se = strel('disk', 50);
    tophatfil = imtophat(Kmedian, se);
    consimage = imadjust(tophatfil);

    % 🔹 การตรวจจับโคโลนี
    extendmaxtran = imextendedmax(consimage, 100);
    firstclean = bwareaopen(extendmaxtran, 1000);
    firstclean = bwpropfilt(firstclean, 'Circularity', [0.1 1]);
    se1 = strel('disk', 15);
    BW = imopen(firstclean, se1);

    % 🔹 ใช้ Distance Transform + Watershed เพื่อลดการรวมกันของโคโลนี
    D = -bwdist(~BW);
    D(~BW) = -Inf;
    L = watershed(D);
    BW(L == 0) = 0;

    % 🔹 กรองขนาดของโคโลนี
    MinSize = 500;
    MaxSize = 5000;
    BW = bwpropfilt(BW, 'Area', [MinSize MaxSize]);

    % 🔹 คำนวณคุณสมบัติของโคโลนี
    stats = regionprops(BW, 'Area', 'Centroid', 'Eccentricity');
    filteredStats = stats([stats.Eccentricity] < 0.9);
    totalCircles = numel(filteredStats);

    % 🔹 แสดงผลลัพธ์
    figure, imshow(img); hold on;
    title(['จำนวนโคโลนีที่ตรวจพบ: ', num2str(totalCircles)]);
    if totalCircles > 0
        centers = cat(1, filteredStats.Centroid);
        plot(centers(:,1), centers(:,2), 'r*', 'MarkerSize', 5, 'LineWidth', 2);
    end
    text(10, 20, ['Colonies: ', num2str(totalCircles)], 'Color', 'white', 'FontSize', 14, 'FontWeight', 'bold');
    hold off;

    % เก็บชื่อไฟล์และจำนวนโคโลนี
    results = [results; {imageFiles(i).name, totalCircles}];

    % บันทึกภาพที่มีข้อความแสดงจำนวนโคโลนี
    outputImagePath = fullfile(outputFolderPath, ['processed_' imageFiles(i).name]);
    print(outputImagePath, '-djpeg');
    close(gcf);
end

% save to excel
outputExcelFile = fullfile(outputFolderPath, 'colony_count_results.xlsx');
table_results = cell2table(results, 'VariableNames', {'Filename', 'ColoniesCount'});
writetable(table_results, outputExcelFile);

% แจ้งผลการบันทึก
disp(['Results saved to: ', outputExcelFile]);