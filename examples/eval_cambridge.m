clear;

%---------------------------------------------------------------------
% Set data folder and testing parameters
%---------------------------------------------------------------------

% Set data folder, change if you have downloaded the data somewhere else
data_root = fullfile(get_root_cnnimageretrieval(), 'data');
cambridge_root = '/usr/stud/zhouq/CambridgeLandmark';

% Set test options
test_datasets = {'ShopFacade', 'KingsCollege', 'OldHospital', 'StMarysChurch'};  % list of datasets to evaluate on
test_imdim = 1024;  % choose test image dimensionality

% Set path to store the result
result_dir = fullfile(data_root, 'cambridge');

% Network configuration
%network_file = fullfile(data_root, 'networks', 'retrieval-SfM-30k', 'retrievalSfM30k-siamac-alex.mat'); % fine-tuned CNN network (siamac-alex or siamac-vgg)
network_file = fullfile(data_root, 'networks', 'retrieval-SfM-30k', 'retrievalSfM30k-siamac-vgg.mat');
use_rvec = 0;  % use R-MAC, otherwise use MAC
use_gpu = 1;  % use GPU (GPUID = use_gpu), otherwise use CPU

%---------------------------------------------------------------------
% Load network model
%---------------------------------------------------------------------
% Prepare function for desc extraction
if ~use_rvec, descfun = @(x, y) cnn_vec (x, y);  else, descfun = @(x, y) cnn_vecr(x, y); end

[~, network_name, ~] = fileparts(network_file);
fprintf('>>Loading CNN image retrieval model %s...\n', network_name);

load(network_file);
net = dagnn.DagNN.loadobj(net);
if use_gpu,     gpuDevice(use_gpu); net.move('gpu'); end

to_extract = 0;
%---------------------------------------------------------------------
% Load whitening variables
%---------------------------------------------------------------------
% Choose training data for whitening and set up data folder
if use_rvec, whiten_tp = 'rmac'; else, whiten_tp = 'mac'; end
whiten_file = fullfile(data_root, 'whiten',  sprintf('Sfm120k-vgg-%s.mat',whiten_tp));
whiten = load(whiten_file);
Lw = whiten.Lw;

%---------------------------------------------------------------------
% Extract descriptor for testing imgs and evaluate
%---------------------------------------------------------------------
% extract and evaluate
for d = 1:numel(test_datasets)
    dataset = test_datasets{d};
    res_file = fullfile(result_dir,  sprintf('%s-vgg-%s-%d.mat', dataset, whiten_tp, test_imdim));
    fprintf('>> %s: Processing test dataset...\n', dataset);
    if to_extract
        [test_path, test_im, n] = get_cambridge_imlist(cambridge_root, dataset, 'dataset_test.txt'); % query images
        [train_path, train_im, n] = get_cambridge_imlist(cambridge_root, dataset, 'dataset_train.txt'); % train images

        fprintf('>> %s: Extracting CNN descriptors for training images...\n', dataset); 
        progressbar(0); vecs = [];   
        for i = 1:n
            vecs{i} = descfun(imresizemaxd(imread(train_path{i}), test_imdim, 0), net);
            progressbar(i/n);
        end
        vecs = cell2mat(vecs);
        save(res_file, 'vecs');

        fprintf('>> %s: Extracting CNN descriptors for query/test images...\n', dataset); 
        progressbar(0); qvecs = [];	
        for i = 1:n
            qvecs{i} = descfun(imresizemaxd(imread(test_path{i}), test_imdim, 0), net);
            progressbar(i/n);
        end
        qvecs = cell2mat(qvecs);
        save(res_file, 'qvecs', '-append');   
    else
        fprintf('>> %s: Load pre-saved descriptors for training and query/test images...\n', dataset); 
        res = load(res_file);
        vecs = res.vecs;
        qvecs = res.qvecs;
    end

    vecsLw = whitenapply(vecs, Lw.m, Lw.P); % apply whitening on database descriptors
    qvecsLw = whitenapply(qvecs, Lw.m, Lw.P); % apply whitening on query descriptors

    % Find k-nearest neighbours
    fprintf('>> %s: K-NearestNeighbour Retrieval...\n', dataset);
    % with learned whitening
    sim = vecsLw'*qvecsLw;
    [sim, ranks] = sort(sim, 'descend');
    idx_file = fullfile(result_dir,  sprintf('%s-vgg-%s-%d-knn.mat', dataset, whiten_tp, test_imdim));
    save(idx_file, 'ranks');
end