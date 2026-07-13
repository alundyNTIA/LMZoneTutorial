%LMZoneTutorial

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

% Distance range

d_km = 1:5:200;   % 1 km to 200 km in 5 km steps

% FSPL model

FSPL_dB = 32.45 + 20*log10(d_km) + 20*log10(f_MHz);

% Diffraction / excess loss

diffraction_loss = 0; % will add terrain dependant model later

% Combine path loss

PL_dB = FSPL_dB + diffraction_loss;

% Compute Aggregate interference (multiple transmitters)
% Convert each transmitters power from dBm to milliwatts. Sum interference
% powers together and convert total interference back to dBm.
% Then calculate total I/N dBm and compare against the protection
% threshold.

I_dBm = Pt_dBm + Gt_dBi + Gr_dBi ...
        - PL_dB ...
        - misc_loss;

num_interferers = 3;

I_mW = 10.^(I_dBm/10);

I_total_mW = num_interferers * I_mW;

I_total_dBm = 10*log10(I_total_mW);

% Compute I/N ratio

I_over_N_dB = I_total_dBm - N_dBm;

% Calculate protection distance

idx = find(I_over_N_dB < I_N_threshold, 1, 'first'); % get the index of the first I/N criteria met

if isempty(idx)
    d_protect_km = NaN;
    disp("Threshold not reached within 200 km range");
else
    d_protect_km = d_km(idx);
end

fprintf("Protection distance: %.2f km\n", d_protect_km);

% Plot (LINEAR SCALE)

% I/N for a single interferer
I_over_N_single = I_dBm - N_dBm;

% I/N for the aggregate interference
I_over_N_aggregate = I_total_dBm - N_dBm;

figure;
plot(d_km, I_over_N_single, 'b-', 'LineWidth', 2); hold on;
plot(d_km, I_over_N_aggregate, 'm--', 'LineWidth', 2);
yline(I_N_threshold,'r--','LineWidth',2);

grid on;
xlabel("Distance (km)");
ylabel("I/N (dB)");
title("Single vs Aggregate Interference");
legend("Single Interferer", ...
    "3 Interferers (Aggregate)", ...
    "-6 dB Threshold", ...
    "Location","best");
