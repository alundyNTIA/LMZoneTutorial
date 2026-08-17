

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

txTable_original = txTable; % saving original network before BS removal

%% Compute distance from each transmitter to the receiver

TxDistance_km = deg2km(distance( ...
    txTable.Latitude, ...
    txTable.Longitude, ...
    RxLat*ones(height(txTable),1), ...
    RxLon*ones(height(txTable),1)));

% Add the distance to the table
txTable.Distance_km = TxDistance_km;

%% Sort by increasing distance

txTable = sortrows(txTable,'Distance_km');

% Keep all transmitters within study area km, study area

MaxCoordDistance = 100;      % km

txTable = txTable(txTable.Distance_km <= MaxCoordDistance,:);

num_interferers = height(txTable);

fprintf('%d transmitters are within %.0f km of the receiver.\n',...
    num_interferers,MaxCoordDistance);

% Extract transmitter information
TxLat = txTable.Latitude';
TxLon = txTable.Longitude';
TxHtm = txTable.Height_M';

% Optional information
TxID = txTable.ID;
RSU  = txTable.RSU;

% Sort transmitters by distance from receiver

% Great-circle distance (km) from each transmitter to the receiver
TxDistance_km = deg2km(distance(TxLat, TxLon, RxLat, RxLon));

% Sort in ascending order of distance
[TxDistance_km, sortIdx] = sort(TxDistance_km);

% Reorder all transmitter information
TxLat = TxLat(sortIdx);
TxLon = TxLon(sortIdx);
TxHtm = TxHtm(sortIdx);

TxID = TxID(sortIdx);
RSU  = RSU(sortIdx);

% (Optional) reorder the table itself
txTable = txTable(sortIdx,:);

fprintf('\nClosest transmitters to receiver\n');
fprintf('--------------------------------------------\n');

for k = 1:num_interferers
    fprintf('TX %-6s  %.2f km\n', ...
        string(TxID(k)), ...
        TxDistance_km(k));
end

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

% Monte Carlo storage
ITM_Loss_MC      = zeros(MCtrials,num_interferers);
P2108_Loss_MC    = zeros(MCtrials,num_interferers);
Total_Loss_MC    = zeros(MCtrials,num_interferers);

RelPct_MC        = zeros(MCtrials,num_interferers);
P2108_Pct_MC     = zeros(MCtrials,num_interferers);

% Monte Carlo storage for received interference
I_dBm_MC = zeros(MCtrials,num_interferers);

%% ITU-R P.2108-1 Terrestrial Clutter Parameters

UseP2108 = true;

% P.2108 terrestrial statistical model:
% Frequency range: 0.5 to 67 GHz
% Minimum distance:
%   0.25 km for one-end correction
%   1.0 km for two-end correction
%
% We use a receiver-end correction because RxHtm = 5 m,
% while the transmitters are approximately 20 m high.

P2108_NumEnds = 1;

% Percentage of locations for P.2108.
%
% IMPORTANT:
% P.2108 defines Lctt as the clutter loss NOT EXCEEDED
% for p percent of locations.
%
% For Monte Carlo modeling, we randomly draw p between
% 0 and 100 for each transmitter and trial.

P2108_MinP = 0.01;
P2108_MaxP = 99.99;

% Storage for P.2108 results
P2108_Loss_MC = zeros(MCtrials,num_interferers);
P2108_Pct_MC  = zeros(MCtrials,num_interferers);

%% Writing tooutput file Allocate output arrays (one row per transmitter per
% Monte Carlo trial)
%{
numRows = MCtrials * num_interferers;

TrialOut    = zeros(numRows,1);
TxLatOut    = zeros(numRows,1);
TxLonOut    = zeros(numRows,1);
TxHeightOut = zeros(numRows,1);

LossOut     = zeros(numRows,1);
RelOut      = zeros(numRows,1);
IOut        = zeros(numRows,1);
INOut       = zeros(numRows,1);
AggOut      = zeros(numRows,1);

row = 1;
%%
%}

% Monte Carlo simulation

for mc = 1:MCtrials

    %trialStartRow = row; % for debug output file only

    % Reset outputs for this trial
    ITM_Loss = zeros(1,num_interferers);
    P2108_Loss = zeros(1,num_interferers);
    
    PMode   = int32(zeros(1,num_interferers));
    ErrNum  = int32(zeros(1,num_interferers));
    Delta_m = zeros(1,num_interferers);

    % Existing transmitter loop
    for k = 1:num_interferers
        %tic
        % Random ITM reliability for this transmitter
        RelPct = 0.01 + 0.98*rand;
        RelPct_MC(mc,k) = RelPct;

        % Random P.2108 percentage of locations
        %
        % P.2108 p is NOT the same thing as ITM reliability.
        % They are independent statistical quantities.

        P2108_Pct = P2108_MinP + ...
            (P2108_MaxP - P2108_MinP)*rand;

        P2108_Pct_MC(mc,k) = P2108_Pct;

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

    % ============================================================
    % ITM PATH LOSS
    % ============================================================

    ITM_Loss(k) = double(loss);


    % ============================================================
    % ITU-R P.2108-1 TERRESTRIAL CLUTTER LOSS
    % ============================================================

    P2108_Loss(k) = ITU_P2108_Terrestrial( ...
        freq/1000, ...
        TxDistance_km(k), ...
        P2108_Pct, ...
        UseP2108);


    % ============================================================
    % TOTAL PROPAGATION LOSS
    % ============================================================

    Total_Loss(k) = ITM_Loss(k) + P2108_Loss(k);


    % ============================================================
    % SAVE MONTE CARLO COMPONENTS
    % ============================================================

    ITM_Loss_MC(mc,k)   = ITM_Loss(k);
    P2108_Loss_MC(mc,k) = P2108_Loss(k);
    Total_Loss_MC(mc,k) = Total_Loss(k);


    % ============================================================
    % LINK BUDGET FOR THIS TRANSMITTER
    % ============================================================

    I_dBm(k) = Pt_dBm ...
        + Gt_dBi ...
        + Gr_dBi ...
        - ITM_Loss(k) ...
        - P2108_Loss(k) ...
        - misc_loss;


    % Save received interference
    I_dBm_MC(mc,k) = I_dBm(k);


    % Diagnostic output
    if mc == 1

        fprintf(['TX %s: Distance = %.2f km, ', ...
            'ITM = %.2f dB, P2108 = %.2f dB, ', ...
            'Total = %.2f dB, I = %.2f dBm\n'], ...
            string(TxID(k)), ...
            d_km, ...
            ITM_Loss(k), ...
            P2108_Loss(k), ...
            Total_Loss(k), ...
            I_dBm(k));

    end

    %% Writing to file
    % Individual transmitter interference (dBm)
    %{
    I_single = Pt_dBm ...
        + Gt_dBi ...
        + Gr_dBi ...
        - dBLoss(k) ...
        - misc_loss;

    IoverN_single = I_single - N_dBm;
    %%
    %}

    dBLoss_MC(mc,k) = dBLoss(k);

    PMode(k)   = pmode;
    ErrNum(k)  = err;
    Delta_m(k) = dist;

    %fprintf('Distance      : %.2f km\n', TxDistance_km(k));

    %% Writing to file
    % Save one output row
    %{
    TrialOut(row)    = mc;
    TxLatOut(row)    = txLat;
    TxLonOut(row)    = txLon;
    TxHeightOut(row) = txHtm;

    LossOut(row)     = dBLoss(k);
    RelOut(row)      = RelPct;
    IOut(row)        = I_single;
    INOut(row)       = IoverN_single;

    row = row + 1;

    %%

    %}

    % Optional progress display every 1000 transmitters
    if mod(k,1000)==0 || k==num_interferers
        fprintf('Processed %d of %d transmitters...\n',k,num_interferers);
    end
%toc

end

% Compute Aggregate interference (multiple transmitters)
% Convert each transmitters power from dBm to milliwatts. Sum interference
% powers together and convert total interference back to dBm.
% Then calculate total I/N dBm and compare against the protection
% threshold.


% ============================================================
% LINK BUDGET
% ============================================================
%
% Received interference power for each transmitter:
%
% I = Pt + Gt + Gr
%     - ITM path loss
%     - P.2108 clutter loss
%     - miscellaneous losses
%
% ============================================================

% ============================================================
% AGGREGATE INTERFERENCE
% ============================================================

% Convert individual transmitter interference from dBm to mW
I_mW = 10.^(I_dBm/10);

% Sum interference powers
I_total_mW = sum(I_mW);

% Convert aggregate power back to dBm
I_total_dBm_MC(mc) = 10*log10(I_total_mW);

% Aggregate I/N
I_over_N_MC(mc) = I_total_dBm_MC(mc) - N_dBm;

AggIn = I_over_N_MC(mc);
%AggOut(trialStartRow:row-1) = AggIn; %debug output file only

end     % <-- End Monte Carlo loop

%% Writing to output file
%% Create output table
%{
OutputTable = table( ...
    TrialOut, ...
    TxLatOut, ...
    TxLonOut, ...
    TxHeightOut, ...
    LossOut, ...
    RelOut, ...
    IOut, ...
    INOut, ...
    AggOut,...
    'VariableNames',{ ...
    'Trial', ...
    'TxLatitude', ...
    'TxLongitude', ...
    'TxHeight_m', ...
    'ITM_PathLoss_dB', ...
    'ITM_Reliability', ...
    'Interference_dBm', ...
    'I_over_N_dB', ...
    'Aggregate_I_over_N_dB'});

writetable(OutputTable,'ITM_MC_Output.xlsx');
writetable(OutputTable,'ITM_MC_Output.csv');

fprintf('\nSaved %d rows to ITM_MC_Output.xlsx\n',height(OutputTable));
%%

%}

% Calculate average path loss from each transmitter

% ============================================================
% MEAN MONTE CARLO LINK BUDGET
% ============================================================

MeanITMLoss   = mean(ITM_Loss_MC,1);
MeanP2108Loss = mean(P2108_Loss_MC,1);

% Total propagation loss
MeanTotalLoss = MeanITMLoss + MeanP2108Loss;


% ============================================================
% MEAN RECEIVED INTERFERENCE
% ============================================================

MeanI_dBm = Pt_dBm ...
    + Gt_dBi ...
    + Gr_dBi ...
    - MeanITMLoss ...
    - MeanP2108Loss ...
    - misc_loss;

I_mW = 10.^(MeanI_dBm/10);

% Calculate each transmitter's aggregate contribution

Iagg_dBm = 10*log10(sum(I_mW));

Contribution_dB = zeros(num_interferers,1);
ContributionPct = zeros(num_interferers,1);

for k = 1:num_interferers

    RemainingPower = sum(I_mW) - I_mW(k);

    Iminus_dBm = 10*log10(RemainingPower);

    Contribution_dB(k) = Iagg_dBm - Iminus_dBm;

    ContributionPct(k) = 100*I_mW(k)/sum(I_mW);

end

% Rank each transmitter
[ContributionPct,idx] = sort(ContributionPct,'descend');

Contribution_dB = Contribution_dB(idx);

TxID = TxID(idx);

TxDistance_km = TxDistance_km(idx);

MeanI_dBm = MeanI_dBm(idx);

MeanITMLoss   = MeanITMLoss(idx);
MeanP2108Loss = MeanP2108Loss(idx);
MeanTotalLoss = MeanTotalLoss(idx);

% Print coordination table
fprintf('\nLink Budget Components\n');
fprintf('--------------------------------------------------------------------------------\n');
fprintf('Rank   ID       Dist(km)   ITM(dB)   P2108(dB)   Misc(dB)   I(dBm)\n');
fprintf('--------------------------------------------------------------------------------\n');

for k = 1:num_interferers

    fprintf('%3d %8s %10.1f %10.2f %11.2f %10.2f %10.2f\n', ...
        k, ...
        string(TxID(k)), ...
        TxDistance_km(k), ...
        MeanITMLoss(k), ...
        MeanP2108Loss(k), ...
        misc_loss, ...
        I_dBm(k));

end

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function Lctt = ITU_P2108_Terrestrial(f_GHz, d_km, p_pct, UseP2108)
%ITU_P2108_TERRESTRIAL
%
% ITU-R P.2108-1 terrestrial statistical clutter loss model.
%
% Inputs:
%   f_GHz    - frequency in GHz
%   d_km     - path distance in km
%   p_pct    - percentage of locations, 0 < p < 100
%   UseP2108 - true/false switch
%
% Output:
%   Lctt     - terrestrial clutter loss in dB
%
% This function implements the one-end terrestrial correction.
%
% Validity:
%   Frequency: 0.5 to 67 GHz
%   Distance:  >= 0.25 km
%   p:         0 < p < 100

    % ---------------------------------------------------------
    % Disable P.2108 if requested
    % ---------------------------------------------------------

    if ~UseP2108
        Lctt = 0;
        return;
    end


    % ---------------------------------------------------------
    % Input validation
    % ---------------------------------------------------------

    if f_GHz < 0.5 || f_GHz > 67
        error('P.2108-1 requires 0.5 <= f <= 67 GHz.');
    end

    if d_km < 0.25
        % P.2108 one-end correction does not apply below 0.25 km.
        Lctt = 0;
        return;
    end

    if p_pct <= 0 || p_pct >= 100
        error('P.2108 percentage must satisfy 0 < p < 100.');
    end


    % ---------------------------------------------------------
    % Long-distance component - Eq. (4a)
    % ---------------------------------------------------------

    Ll = -2 * log10( ...
        10.^(-5*log10(f_GHz) - 12.5) + ...
        10.^(-16.5));

    sigma_l = 4;


    % ---------------------------------------------------------
    % Short-distance component - Eq. (5a)
    % ---------------------------------------------------------

    Ls = 32.98 ...
        + 23.9 * log10(d_km) ...
        + 3 * log10(f_GHz);

    sigma_s = 6;


    % ---------------------------------------------------------
    % Combined standard deviation - Eq. (3b)
    % ---------------------------------------------------------

    A = 10.^(-0.2 * Ll);
    B = 10.^(-0.2 * Ls);

    sigma_cb = sqrt( ...
        (sigma_l^2 * A + sigma_s^2 * B) / ...
        (A + B));


    % ---------------------------------------------------------
    % Inverse Q function
    % ---------------------------------------------------------

    Qinv = sqrt(2) * erfcinv(2 * p_pct / 100);


    % ---------------------------------------------------------
    % Clutter loss - Eq. (3a)
    % ---------------------------------------------------------

    Lctt = ...
        -5 * log10(A + B) ...
        - sigma_cb * Qinv;


    % ---------------------------------------------------------
    % Maximum clutter loss - Eq. (6)
    %
    % Evaluate the model at 2 km.
    % ---------------------------------------------------------

    d_2km = 2.0;

    Ls_2km = ...
        32.98 ...
        + 23.9 * log10(d_2km) ...
        + 3 * log10(f_GHz);

    B_2km = 10.^(-0.2 * Ls_2km);

    sigma_cb_2km = sqrt( ...
        (sigma_l^2 * A + sigma_s^2 * B_2km) / ...
        (A + B_2km));

    Lctt_2km = ...
        -5 * log10(A + B_2km) ...
        - sigma_cb_2km * Qinv;


    % ---------------------------------------------------------
    % Apply maximum-loss limit
    % ---------------------------------------------------------

    Lctt = min(Lctt, Lctt_2km);


    % ---------------------------------------------------------
    % Final sanity check
    % ---------------------------------------------------------

    if ~isfinite(Lctt)
        error('P.2108 calculation returned a non-finite value.');
    end

end