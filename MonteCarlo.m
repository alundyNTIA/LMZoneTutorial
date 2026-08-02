

% The purpose of this code is to demonstrate a simplistic
% compliance/noncompliance framework for determining harmful interference at
% the output of the receiver antenna

% System parameters

Pt_dBm = 46;
Gt_dBi = 15;
Gr_dBi = 10;

f_MHz = 4400;
BW_Hz = 1e6;
NF_dB = 5;

misc_loss = 5;

I_N_threshold = -6;

% Noise floor

kT_dBmHz = -174;
N_dBm = kT_dBmHz + 10*log10(BW_Hz) + NF_dB;

% Receiver 
% Eventually modify to have a list of receiver locations for LM
RxLat = 38.4000;
RxLon = -77.2000;
RxHtm = 5.0;

% Three interfering transmitters
%{
%% Read from csv file
TxLat = [24.55478848 24.5700912438 24.57031318];
TxLon = [-81.80757429 -81.77097236 -81.73660619];
TxHtm = [20.0 20.0 20.0];

num_interferers = length(TxLat);
%}

% Read transmitter locations from randomize real

csvFile = 'RandomReal.xlsx';

disp(which(csvFile))

if ~isfile(csvFile)
    error('Cannot find %s', csvFile);
end

txTable = readtable(csvFile);

% Keep only the first 10 transmitters (or fewer if the file has <10)
num_interferers = min(10, height(txTable));
txTable = txTable(1:num_interferers,:);

% Extract transmitter information
TxLat = txTable.Latitude';
TxLon = txTable.Longitude';
TxHtm = txTable.Height_M';

% Optional information
TxID = txTable.ID;
RSU  = txTable.RSU;

fprintf('Loaded %d transmitters from %s\n', num_interferers, csvFile);


%% ITM Parameters
% Calling DLL that uses locally stored terrain and ITM functions
NET.addAssembly(fullfile('C:\USGS\USGS\', 'SEADLib.dll'));
%itmp=ITMAcs.ITMP2P;

% pol: 0-Horizontal, 1-Vertical
% radio_climate: 1-Equatorial, 2-Continental Subtropical, 3-Maritime Tropical,
%                4-Desert, 5-Continental Temperate, 6-Maritime Temperate, Over Land,
%                7-Maritime Temperate, Over Sea
% conf, rel: 0.01 to 0.99
% elev[]: num points, delta dist(m), height(m) point1, ..., height(m) point n
% PropMode: 0 LOS, 4 Single Horizon, 5 Difraction Double Horizon, 
%           8 Double Horizon, 9 Difraction Single Horizon, 6 Troposcatter Single Horizon, 
%           10 Troposcatter Double Horizon, 333 Error
% errnum: 0- No Error.
%         1- Warning: Some parameters are nearly out of range.
%                     Results should be used with caution.
%         2- Note: Default parameters have been substituted for impossible ones.
%         3- Warning: A combination of parameters is out of range.
%                     Results are probably invalid.
%         Other-  Warning: Some parameters are out of range.
%                          Results are probably invalid.

Refrac = 301.0;
Conduct = 0.005;
Dielectric = 15.0;

Polarity      = int32(1);      % Vertical
RadioClimate  = int32(5);      % Continental Temperate
ConfPct       = 0.50;          % This is actually 50%, not 0.5% 
RelPct        = 0.50;

FreqMHz = f_MHz*ones(1,num_interferers);

TerHandler   = int32(1);        % USGS 3 arc-second
TerDirectory = 'C:\USGS\USGS\';



% Call the ITM DLL

itmp = ITMAcs.ITMP2P;

% Monte Carlo parameters

MCtrials = 100; % Number of Monte Carlo trials

I_total_dBm_MC = zeros(MCtrials,1);
I_over_N_MC    = zeros(MCtrials,1);
RelPct_MC      = zeros(MCtrials,1);

dBLoss_MC = zeros(MCtrials,num_interferers);

% Monte Carlo simulation

for mc = 1:MCtrials

    % Draw ITM reliability from Uniform(0.01,0.99)
    RelPct = 0.01 + 0.98*rand;

    RelPct_MC(mc) = RelPct;

    % Reset outputs for this realization
    dBLoss  = zeros(1,num_interferers);
    PMode   = int32(zeros(1,num_interferers));
    ErrNum  = int32(zeros(1,num_interferers));
    Delta_m = zeros(1,num_interferers);

    % Existing transmitter loop
    for k = 1:num_interferers
tic
% Random ITM reliability for this transmitter
RelPct = 0.01 + 0.98*rand;
    % Single-element inputs
    txLat = TxLat(k);
    txLon = TxLon(k);
    txHtm = TxHtm(k);
    freq  = FreqMHz(k);

    % Outputs for this transmitter
    loss  = 0;
    pmode = int32(0);
    err   = int32(0);
    dist  = 0;

    [loss, pmode, err, dist] = ...
        itmp.ITMp2pAry( ...
        txHtm,...
        RxHtm,...
        Refrac,...
        Conduct,...
        Dielectric,...
        freq,...
        RadioClimate,...
        Polarity,...
        ConfPct,...
        RelPct,...
        txLat,...
        txLon,...
        RxLat,...
        RxLon,...
        TerHandler,...
        TerDirectory,...
        loss,...
        pmode,...
        err,...
        dist);

    dBLoss(k)  = double(loss);
    dBLoss_MC(mc,k) = dBLoss(k);

    PMode(k)   = pmode;
    ErrNum(k)  = err;
    Delta_m(k) = dist;

    tx_rx_distance = deg2km(distance(txLat,txLon,RxLat,RxLon));

    fprintf('TX %d Distance: %.2f km\n', k, tx_rx_distance);

    % Optional progress display every 1000 transmitters
    if mod(k,1000)==0 || k==num_interferers
        fprintf('Processed %d of %d transmitters...\n',k,num_interferers);
    end
toc
%fprintf('  Distance      : %.1f km\n', Delta_m(k)/1000);
end

% Compute Aggregate interference (multiple transmitters)
% Convert each transmitters power from dBm to milliwatts. Sum interference
% powers together and convert total interference back to dBm.
% Then calculate total I/N dBm and compare against the protection
% threshold.

% Aggregate interference for this realization

I_dBm = Pt_dBm ...
    + Gt_dBi ...
    + Gr_dBi ...
    - dBLoss ...
    - misc_loss;

I_mW = 10.^(I_dBm/10);
I_total_mW = sum(I_mW);
I_total_dBm_MC(mc) = 10*log10(I_total_mW);
I_over_N_MC(mc) = I_total_dBm_MC(mc) - N_dBm;

end     % <-- End Monte Carlo loop


fprintf('\nMonte Carlo Results\n');

fprintf('Mean Aggregate I/N = %.2f dB\n',mean(I_over_N_MC));

fprintf('Median Aggregate I/N = %.2f dB\n',median(I_over_N_MC));

fprintf('Std Dev = %.2f dB\n',std(I_over_N_MC));

fprintf('Minimum = %.2f dB\n',min(I_over_N_MC));

fprintf('Maximum = %.2f dB\n',max(I_over_N_MC));

Pexceed = mean(I_over_N_MC > I_N_threshold);

fprintf('Probability of Exceedance = %.4f\n',Pexceed);


%{
commenting this section because transmitters are fixed
% Calculate protection distance

idx = find(I_over_N_dB < I_N_threshold, 1, 'first'); % get the index of the first I/N criteria met

if isempty(idx)
    d_protect_km = NaN;
    disp("Threshold not reached within 200 km range");
else
    d_protect_km = d_km(idx);
end

fprintf("Protection distance: %.2f km\n", d_protect_km);
%}

% Summary Data
fprintf('\nInterferer Summary\n');

for k=1:num_interferers

    fprintf('TX %d\n',k);
    %fprintf('  Distance      : %.1f km\n',Delta_m(k)/1000);
    fprintf('  Path Loss     : %.2f dB\n',dBLoss(k));
    fprintf('  Mode          : %d\n',PMode(k));
    fprintf('  Error Code    : %d\n',ErrNum(k));
    fprintf('  Interference  : %.2f dBm\n\n',I_dBm(k));

end

fprintf('Aggregate Interference = %.2f dBm\n',I_total_dBm);
fprintf('I/N = %.2f dB\n',I_over_N_dB);

if I_over_N_dB <= I_N_threshold
    disp("Protection criterion not exceeded.")
else
    disp("Protection criterion exceeded.")
end

%% Plot
figure

figure
histogram(I_over_N_MC,30)
xlabel('I/N')
ylabel('Probability Density')
title('Distribution of I/N')

% CDF of Aggregate I/N

figure
cdfplot(I_over_N_MC)

hold on
xline(I_N_threshold,'r--','LineWidth',2)

xlabel('Aggregate I/N (dB)')
ylabel('Cumulative Probability')
title('CDF of Aggregate I/N')
grid on

hold on

xline(I_N_threshold,'r--','LineWidth',2)

xlabel('Aggregate I/N (dB)')
ylabel('Number of Trials')
title('Monte Carlo Distribution of Aggregate I/N')
grid on

grid on
labels = arrayfun(@(k) sprintf('TX%d',k), 1:num_interferers, ...
    'UniformOutput', false);
labels{end+1} = 'Aggregate';

xticklabels(labels)
ylabel('Interference (dBm)')
title('Received Interference')
figure
bar(I_over_N_dB)

hold on

yline(I_N_threshold,'r--','LineWidth',2)
ylabel('I/N (dB)')
title('Aggregate I/N')
grid on
%%

figure
histogram(I_over_N_MC,25,'Normalization','pdf')

hold on
xline(I_N_threshold,'r--','LineWidth',2)

xlabel('Aggregate I/N (dB)')
ylabel('Probability Density')
title('Distribution of Aggregate I/N')
grid on

figure
histogram(I_over_N_MC,25,'Normalization','pdf')

figure
histogram(dBLoss_MC(:),30,'Normalization','pdf')

xlabel('ITM Path Loss (dB)')
ylabel('Probability Density')
title('Distribution of ITM Path Loss')
grid on