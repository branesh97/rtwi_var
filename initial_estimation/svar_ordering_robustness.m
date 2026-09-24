%% ================================================================
%  AUSTRALIAN DOLLAR SVAR - ORDERING ROBUSTNESS
%
%  Sample: 1995Q1 - 2026Q2
%
%  Purpose:
%  Test sensitivity of the commodity, VIX and relative-yield results
%  to recursive ordering assumptions.
%
%  FOUR ORDERINGS
%
%  Model A - baseline/current:
%    US GDP -> Commodity -> VIX
%    AU GDP -> Inflation -> Spread -> RTWI
%
%  Model B - swap VIX and Commodity:
%    US GDP -> VIX -> Commodity
%    AU GDP -> Inflation -> Spread -> RTWI
%
%  Model C - swap Spread and RTWI:
%    US GDP -> Commodity -> VIX
%    AU GDP -> Inflation -> RTWI -> Spread
%
%  Model D - swap both:
%    US GDP -> VIX -> Commodity
%    AU GDP -> Inflation -> RTWI -> Spread
%
%  In every model:
%    first 3 variables = foreign block
%    p = 2
%    no deterministic crisis controls
%
%% ================================================================

clear;
clc;
close all;


%% 1. PRELIMINARY

folder = fileparts(mfilename('fullpath'));

addpath(fullfile(folder,'_func'));


filePath = ...
    fullfile(folder,'data','data_collected.xlsx');


figDir = ...
    fullfile(folder,'figures');

if ~exist(figDir,'dir')
    mkdir(figDir);
end


resultDir = ...
    fullfile(folder,'results');

if ~exist(resultDir,'dir')
    mkdir(resultDir);
end


assert(exist('olsvar_soe','file') == 2, ...
    'olsvar_soe.m not found.');

assert(exist('calculate_IRF_FEVD','file') == 2, ...
    'calculate_IRF_FEVD.m not found.');


%% 2. IMPORT DATA

data = readtable( ...
    filePath, ...
    'Sheet','data', ...
    'VariableNamingRule','preserve');


data = standardizeMissing( ...
    data, ...
    {'NA','N/A','na',''});


%% 3. DATE VARIABLES

dateVars = { ...
    'quarter_start', ...
    'quarter_end'};


for ii = 1:length(dateVars)

    v = dateVars{ii};

    if ~isdatetime(data.(v))

        if isnumeric(data.(v))

            data.(v) = datetime( ...
                data.(v), ...
                'ConvertFrom','excel');

        else

            data.(v) = ...
                datetime(data.(v));

        end

    end

end


%% 4. MAKE REMAINING VARIABLES NUMERIC

varNames = ...
    data.Properties.VariableNames;


for jj = 3:width(data)

    v = varNames{jj};

    if ~isnumeric(data.(v))

        data.(v) = ...
            str2double(string(data.(v)));

    end

end


%% 5. YEARLAB

yr = year(data.quarter_start);

qtr = ...
    ceil(month(data.quarter_start)/3);


yearlab = ...
    yr + (qtr-1)/4;


quarterlab = ...
    string(yr) + "Q" + string(qtr);


%% 6. SAMPLE

sampleStart = ...
    datetime(1995,1,1);

sampleEnd = ...
    datetime(2026,4,1);


sample = ...
    data.quarter_start >= sampleStart & ...
    data.quarter_start <= sampleEnd;


D = data(sample,:);

yearlab_svar = ...
    yearlab(sample);

quarterlab_svar = ...
    quarterlab(sample);


T = height(D);


assert(T == 126, ...
    'Unexpected sample size.');


fprintf('\n============================================================\n');
fprintf('SVAR ORDERING ROBUSTNESS\n');
fprintf('============================================================\n');

fprintf('Sample: %s to %s\n', ...
    char(quarterlab_svar(1)), ...
    char(quarterlab_svar(end)));

fprintf('T = %d\n',T);


%% 7. CHECK REQUIRED VARIABLES

requiredVars = { ...
    'us_rgdp', ...
    'comm_price', ...
    'vix', ...
    'au_rgdp', ...
    'au_inf_trim', ...
    'au_us_2yr', ...
    'rtwi'};


for ii = 1:length(requiredVars)

    v = requiredVars{ii};

    assert( ...
        ismember(v,D.Properties.VariableNames), ...
        'Missing variable: %s',v);

    assert( ...
        all(isfinite(D.(v))), ...
        'Variable %s has missing observations.',v);

end


%% 8. TRANSFORM VARIABLES
%
% Same transformations as svar_initial.m


log_us_gdp = ...
    100*log(D.us_rgdp);

log_comm = ...
    100*log(D.comm_price);

log_vix = ...
    100*log(D.vix);

log_au_gdp = ...
    100*log(D.au_rgdp);

trim_inf = ...
    D.au_inf_trim;

spread_2yr = ...
    D.au_us_2yr;

log_rtwi = ...
    100*log(D.rtwi);


%% 9. QUADRATIC GDP DETRENDING

tt = (1:T)';


Xtrend = [ ...
    ones(T,1) ...
    tt ...
    tt.^2];


% US GDP
b_us = ...
    Xtrend \ log_us_gdp;

trend_us = ...
    Xtrend*b_us;

us_gdp_gap = ...
    log_us_gdp - trend_us;


% Australian GDP
b_au = ...
    Xtrend \ log_au_gdp;

trend_au = ...
    Xtrend*b_au;

au_gdp_gap = ...
    log_au_gdp - trend_au;


%% 10. CANONICAL DATASET
%
% This is NOT necessarily the recursive ordering.
%
% It is simply the base matrix from which all four recursive
% orderings are constructed.


Ybase = [ ...
    us_gdp_gap ...
    log_comm ...
    log_vix ...
    au_gdp_gap ...
    trim_inf ...
    spread_2yr ...
    log_rtwi];


baseKeys = { ...
    'USGDP', ...
    'Commodity', ...
    'VIX', ...
    'AUGDP', ...
    'Inflation', ...
    'Spread', ...
    'RTWI'};


baseLabels = { ...
    'US Real GDP', ...
    'Commodity Prices', ...
    'VIX', ...
    'Australian Real GDP', ...
    'Trimmed Mean Inflation', ...
    'AU-US 2yr Spread', ...
    'Real TWI'};


assert(~any(isnan(Ybase(:))));
assert(~any(isinf(Ybase(:))));


%% 11. FOUR ORDERINGS
%
% Indices refer to columns in Ybase.


modelNames = { ...
    'A_Baseline', ...
    'B_VIX_before_Commodity', ...
    'C_RTWI_before_Spread', ...
    'D_Swap_Both'};


modelShort = { ...
    'A: C -> VIX; Spread -> RTWI', ...
    'B: VIX -> C; Spread -> RTWI', ...
    'C: C -> VIX; RTWI -> Spread', ...
    'D: VIX -> C; RTWI -> Spread'};


% A
orderIdx{1} = ...
    [1 2 3 4 5 6 7];

% B
orderIdx{2} = ...
    [1 3 2 4 5 6 7];

% C
orderIdx{3} = ...
    [1 2 3 4 5 7 6];

% D
orderIdx{4} = ...
    [1 3 2 4 5 7 6];


M = length(modelNames);


%% 12. MODEL SETTINGS

p = 2;

n_foreign = 3;

hor = 24;

hor_fevd = 40;


% FEVD forecast horizons
fevdHorizons = [ ...
    1 ...
    4 ...
    8 ...
    12 ...
    20 ...
    40];


% Presentation normalizations
size_comm_shock = 10;      % +10 log points
size_vix_shock = 10;       % +10 log points
size_spread_shock = 1;     % +1 ppt = 100 bp


% No deterministic controls
d = [];


%% 13. STORAGE

results_order = struct([]);


rtwiIRF_comm = ...
    nan(M,hor+1);

rtwiIRF_vix = ...
    nan(M,hor+1);

rtwiIRF_spread = ...
    nan(M,hor+1);


FEVD_comm = ...
    nan(M,length(fevdHorizons));

FEVD_vix = ...
    nan(M,length(fevdHorizons));

FEVD_spread = ...
    nan(M,length(fevdHorizons));

FEVD_fx = ...
    nan(M,length(fevdHorizons));


maxRoots = ...
    nan(M,1);


% Diagnostics for normalized IRFs
commImpact = nan(M,1);
commPeak = nan(M,1);
commPeakH = nan(M,1);

vixImpact = nan(M,1);
vixPeak = nan(M,1);
vixPeakH = nan(M,1);

spreadImpact = nan(M,1);
spreadPeak = nan(M,1);
spreadPeakH = nan(M,1);


% One-standard-deviation structural shock sizes
sdCommodity = nan(M,1);
sdVIX = nan(M,1);
sdSpread = nan(M,1);


%% 14. ESTIMATE ALL FOUR MODELS

for mm = 1:M

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('MODEL %s\n',modelNames{mm});
    fprintf('============================================================\n');


    %% ORDER DATA

    idx = orderIdx{mm};

    y = Ybase(:,idx);

    keys = baseKeys(idx);

    labels = baseLabels(idx);

    N = size(y,2);


    fprintf('Ordering:\n');

    for kk = 1:N
        fprintf('  %d. %s\n',kk,labels{kk});
    end


    %% LOCATE VARIABLES IN THIS ORDERING

    posUS = ...
        find(strcmp(keys,'USGDP'));

    posComm = ...
        find(strcmp(keys,'Commodity'));

    posVIX = ...
        find(strcmp(keys,'VIX'));

    posAUGDP = ...
        find(strcmp(keys,'AUGDP'));

    posInf = ...
        find(strcmp(keys,'Inflation'));

    posSpread = ...
        find(strcmp(keys,'Spread'));

    posRTWI = ...
        find(strcmp(keys,'RTWI'));


    %% ESTIMATE SOE VAR

    [phi,gamma,SIGMA,X,e] = ...
        olsvar_soe( ...
            y, ...
            p, ...
            d, ...
            n_foreign);


    %% STABILITY

    Companion = [ ...
        phi(2:end,:)'; ...
        eye(N*(p-1)) zeros(N*(p-1),N)];


    rootsVAR = ...
        eig(Companion);


    maxRoot = ...
        max(abs(rootsVAR));


    maxRoots(mm) = ...
        maxRoot;


    fprintf('Maximum root = %.4f\n', ...
        maxRoot);


    if maxRoot >= 1

        warning( ...
            'Model %s is unstable.', ...
            modelNames{mm});

    end


    %% CHOLESKY IDENTIFICATION

    [~,cholFlag] = chol(SIGMA);

    assert(cholFlag == 0, ...
        'SIGMA is not positive definite.');


    B = ...
        chol(SIGMA,'lower');


    %% STORE ONE-SD SHOCK SIZES
    %
    % Diagonal entries give the contemporaneous own-variable response
    % to a one-standard-deviation structural shock.

    sdCommodity(mm) = ...
        B(posComm,posComm);

    sdVIX(mm) = ...
        B(posVIX,posVIX);

    sdSpread(mm) = ...
        B(posSpread,posSpread);


    %% ------------------------------------------------------------
    % COMMODITY SHOCK
    %% ------------------------------------------------------------

    respComm = ...
        normalizedShockResponse( ...
            phi, ...
            B, ...
            posComm, ...
            size_comm_shock, ...
            hor);


    rtwiComm = ...
        respComm(posRTWI,:);


    rtwiIRF_comm(mm,:) = ...
        rtwiComm;


    commImpact(mm) = ...
        rtwiComm(1);


    [~,peakInd] = ...
        max(abs(rtwiComm));


    commPeak(mm) = ...
        rtwiComm(peakInd);

    commPeakH(mm) = ...
        peakInd-1;


    %% ------------------------------------------------------------
    % VIX SHOCK
    %% ------------------------------------------------------------

    respVIX = ...
        normalizedShockResponse( ...
            phi, ...
            B, ...
            posVIX, ...
            size_vix_shock, ...
            hor);


    rtwiVIX = ...
        respVIX(posRTWI,:);


    rtwiIRF_vix(mm,:) = ...
        rtwiVIX;


    vixImpact(mm) = ...
        rtwiVIX(1);


    [~,peakInd] = ...
        max(abs(rtwiVIX));


    vixPeak(mm) = ...
        rtwiVIX(peakInd);

    vixPeakH(mm) = ...
        peakInd-1;


    %% ------------------------------------------------------------
    % RELATIVE-YIELD SHOCK
    %% ------------------------------------------------------------

    respSpread = ...
        normalizedShockResponse( ...
            phi, ...
            B, ...
            posSpread, ...
            size_spread_shock, ...
            hor);


    rtwiSpread = ...
        respSpread(posRTWI,:);


    rtwiIRF_spread(mm,:) = ...
        rtwiSpread;


    spreadImpact(mm) = ...
        rtwiSpread(1);


    [~,peakInd] = ...
        max(abs(rtwiSpread));


    spreadPeak(mm) = ...
        rtwiSpread(peakInd);

    spreadPeakH(mm) = ...
        peakInd-1;


    %% ------------------------------------------------------------
    % CHECK SOE RESTRICTION
    %
    % A domestic relative-yield shock must not move any of the first
    % three foreign variables at any horizon.
    %% ------------------------------------------------------------

    maxForeignResponseSpread = ...
        max(abs(respSpread(1:n_foreign,:)),[], 'all');


    assert( ...
        maxForeignResponseSpread < 1e-10, ...
        'SOE restriction failed for spread shock.');


    %% ------------------------------------------------------------
    % FEVD
    %% ------------------------------------------------------------

    [~,FEVD] = ...
        calculate_IRF_FEVD( ...
            phi, ...
            B, ...
            hor_fevd, ...
            'FEVD');


    rtwiFEVD = ...
        squeeze( ...
            FEVD( ...
                posRTWI, ...
                :, ...
                fevdHorizons));


    assert( ...
        size(rtwiFEVD,1) == N);


    assert( ...
        max(abs(sum(rtwiFEVD,1)-100)) < 1e-8);


    FEVD_comm(mm,:) = ...
        rtwiFEVD(posComm,:);

    FEVD_vix(mm,:) = ...
        rtwiFEVD(posVIX,:);

    FEVD_spread(mm,:) = ...
        rtwiFEVD(posSpread,:);

    FEVD_fx(mm,:) = ...
        rtwiFEVD(posRTWI,:);


    %% ------------------------------------------------------------
    % SAVE MODEL RESULTS
    %% ------------------------------------------------------------

    results_order(mm).name = ...
        modelNames{mm};

    results_order(mm).ordering = ...
        labels;

    results_order(mm).keys = ...
        keys;

    results_order(mm).phi = ...
        phi;

    results_order(mm).gamma = ...
        gamma;

    results_order(mm).SIGMA = ...
        SIGMA;

    results_order(mm).B = ...
        B;

    results_order(mm).max_root = ...
        maxRoot;

    results_order(mm).resp_commodity = ...
        respComm;

    results_order(mm).resp_vix = ...
        respVIX;

    results_order(mm).resp_spread = ...
        respSpread;

    results_order(mm).rtwi_commodity = ...
        rtwiComm;

    results_order(mm).rtwi_vix = ...
        rtwiVIX;

    results_order(mm).rtwi_spread = ...
        rtwiSpread;

    results_order(mm).FEVD = ...
        FEVD;

    results_order(mm).rtwi_FEVD = ...
        rtwiFEVD;

end


%% 15. SUMMARY TABLE

SummaryTable = table( ...
    string(modelNames(:)), ...
    maxRoots, ...
    sdCommodity, ...
    sdVIX, ...
    sdSpread, ...
    commImpact, ...
    commPeak, ...
    commPeakH, ...
    vixImpact, ...
    vixPeak, ...
    vixPeakH, ...
    spreadImpact, ...
    spreadPeak, ...
    spreadPeakH, ...
    'VariableNames', ...
    { ...
    'Model', ...
    'MaxRoot', ...
    'Commodity_1SD_Size', ...
    'VIX_1SD_Size', ...
    'Spread_1SD_Size', ...
    'Commodity_Impact_RTWI', ...
    'Commodity_Peak_RTWI', ...
    'Commodity_Peak_Horizon', ...
    'VIX_Impact_RTWI', ...
    'VIX_Peak_RTWI', ...
    'VIX_Peak_Horizon', ...
    'Spread_Impact_RTWI', ...
    'Spread_Peak_RTWI', ...
    'Spread_Peak_Horizon'});


fprintf('\n');
fprintf('============================================================\n');
fprintf('ORDERING ROBUSTNESS SUMMARY\n');
fprintf('============================================================\n');

disp(SummaryTable);


%% 16. ORDERING-DEFINITION TABLE

orderingString = strings(M,1);


for mm = 1:M

    idx = orderIdx{mm};

    thisLabels = ...
        baseLabels(idx);

    orderingString(mm) = ...
        strjoin(thisLabels,' -> ');

end


OrderingTable = table( ...
    string(modelNames(:)), ...
    orderingString, ...
    'VariableNames', ...
    {'Model','Ordering'});


%% 17. RTWI IRF COMPARISON
%
% Same economically-sized normalized shock in all four models.


h = 0:hor;


figure( ...
    'Color','w', ...
    'Position',[100 100 1200 400]);


tiledlayout( ...
    1,3, ...
    'TileSpacing','compact', ...
    'Padding','compact');


%% COMMODITY

nexttile;

hold on;

for mm = 1:M

    plot( ...
        h, ...
        rtwiIRF_comm(mm,:), ...
        'LineWidth',1.7);

end

yline( ...
    0, ...
    'k:', ...
    'HandleVisibility','off');

grid on;
box off;

title('+10% commodity-price shock');

xlabel('Quarters');
ylabel('Real TWI response (%)');

xlim([0 hor]);

legend( ...
    modelShort, ...
    'Location','best', ...
    'FontSize',8);


%% VIX

nexttile;

hold on;

for mm = 1:M

    plot( ...
        h, ...
        rtwiIRF_vix(mm,:), ...
        'LineWidth',1.7);

end

yline( ...
    0, ...
    'k:', ...
    'HandleVisibility','off');

grid on;
box off;

title('+10% VIX shock');

xlabel('Quarters');
ylabel('Real TWI response (%)');

xlim([0 hor]);


%% SPREAD

nexttile;

hold on;

for mm = 1:M

    plot( ...
        h, ...
        rtwiIRF_spread(mm,:), ...
        'LineWidth',1.7);

end

yline( ...
    0, ...
    'k:', ...
    'HandleVisibility','off');

grid on;
box off;

title('+100 bp AU-US 2yr spread shock');

xlabel('Quarters');
ylabel('Real TWI response (%)');

xlim([0 hor]);


sgtitle( ...
    'RTWI Impulse Responses Across Recursive Orderings');


exportgraphics( ...
    gcf, ...
    fullfile(figDir, ...
    '13_svar_ordering_robustness_irfs.png'), ...
    'Resolution',300);


%% 18. FEVD COMPARISON FIGURE

figure( ...
    'Color','w', ...
    'Position',[100 80 1050 760]);


tiledlayout( ...
    2,2, ...
    'TileSpacing','compact', ...
    'Padding','compact');


%% COMMODITY FEVD

nexttile;

hold on;

for mm = 1:M

    plot( ...
        fevdHorizons, ...
        FEVD_comm(mm,:), ...
        '-o', ...
        'LineWidth',1.5);

end

grid on;
box off;

title('Commodity-price shock');

xlabel('Forecast horizon');
ylabel('Share of RTWI FE variance (%)');

xticks(fevdHorizons);

legend( ...
    modelShort, ...
    'Location','best', ...
    'FontSize',8);


%% VIX FEVD

nexttile;

hold on;

for mm = 1:M

    plot( ...
        fevdHorizons, ...
        FEVD_vix(mm,:), ...
        '-o', ...
        'LineWidth',1.5);

end

grid on;
box off;

title('VIX shock');

xlabel('Forecast horizon');
ylabel('Share of RTWI FE variance (%)');

xticks(fevdHorizons);


%% SPREAD FEVD

nexttile;

hold on;

for mm = 1:M

    plot( ...
        fevdHorizons, ...
        FEVD_spread(mm,:), ...
        '-o', ...
        'LineWidth',1.5);

end

grid on;
box off;

title('AU-US 2yr spread shock');

xlabel('Forecast horizon');
ylabel('Share of RTWI FE variance (%)');

xticks(fevdHorizons);


%% RESIDUAL FX SHOCK FEVD

nexttile;

hold on;

for mm = 1:M

    plot( ...
        fevdHorizons, ...
        FEVD_fx(mm,:), ...
        '-o', ...
        'LineWidth',1.5);

end

grid on;
box off;

title('Residual exchange-rate shock');

xlabel('Forecast horizon');
ylabel('Share of RTWI FE variance (%)');

xticks(fevdHorizons);


sgtitle( ...
    'RTWI FEVD Across Recursive Orderings');


exportgraphics( ...
    gcf, ...
    fullfile(figDir, ...
    '14_svar_ordering_robustness_fevd.png'), ...
    'Resolution',300);


%% 19. BUILD LONG-FORM FEVD TABLE

FEVD_Long = table();


for mm = 1:M

    for hh = 1:length(fevdHorizons)

        newRow = table( ...
            string(modelNames{mm}), ...
            fevdHorizons(hh), ...
            FEVD_comm(mm,hh), ...
            FEVD_vix(mm,hh), ...
            FEVD_spread(mm,hh), ...
            FEVD_fx(mm,hh), ...
            'VariableNames', ...
            { ...
            'Model', ...
            'Horizon', ...
            'Commodity', ...
            'VIX', ...
            'Spread', ...
            'ResidualFX'});

        FEVD_Long = ...
            [FEVD_Long; newRow];

    end

end


fprintf('\n');
fprintf('============================================================\n');
fprintf('HEADLINE RTWI FEVD ACROSS ORDERINGS\n');
fprintf('============================================================\n');

disp(FEVD_Long);


%% 20. HORIZON-SPECIFIC COMPARISON TABLES
%
% Particularly useful for reading H1, H8 and H20 results quickly.


compareH = [1 8 20];


FEVD_Selected = table();


for hh = compareH

    col = ...
        find(fevdHorizons == hh);

    for mm = 1:M

        newRow = table( ...
            string(modelNames{mm}), ...
            hh, ...
            FEVD_comm(mm,col), ...
            FEVD_vix(mm,col), ...
            FEVD_spread(mm,col), ...
            FEVD_fx(mm,col), ...
            'VariableNames', ...
            { ...
            'Model', ...
            'Horizon', ...
            'Commodity', ...
            'VIX', ...
            'Spread', ...
            'ResidualFX'});

        FEVD_Selected = ...
            [FEVD_Selected;newRow];

    end

end


disp(' ');
disp('Selected FEVD horizons:');
disp(FEVD_Selected);


%% 20A. COMBINED FEVD SHARES ACROSS ORDERINGS
%
% These groups are useful because swapping the recursive ordering
% within each pair reallocates variance between the two shocks but
% should leave their combined contribution essentially unchanged.
%
% Group 1:
%   Commodity-price shock + VIX shock
%
% Group 2:
%   AU-US 2yr spread shock + residual exchange-rate shock
%
% NOTE:
% These two groups do NOT sum to 100 because US GDP, Australian GDP
% and inflation shocks remain outside them.


FEVD_comm_vix = ...
    FEVD_comm + FEVD_vix;


FEVD_spread_fx = ...
    FEVD_spread + FEVD_fx;


%% CHECK INVARIANCE ACROSS THE FOUR ORDERINGS

commVIX_reference = ...
    FEVD_comm_vix(1,:);

spreadFX_reference = ...
    FEVD_spread_fx(1,:);


maxDiff_commVIX = ...
    max( ...
    abs( ...
    FEVD_comm_vix - ...
    commVIX_reference), ...
    [], ...
    'all');


maxDiff_spreadFX = ...
    max( ...
    abs( ...
    FEVD_spread_fx - ...
    spreadFX_reference), ...
    [], ...
    'all');


fprintf('\n');
fprintf('============================================================\n');
fprintf('COMBINED FEVD INVARIANCE CHECK\n');
fprintf('============================================================\n');

fprintf('Maximum difference across orderings:\n');

fprintf('Commodity + VIX:          %.12f percentage points\n', ...
    maxDiff_commVIX);

fprintf('Spread + Residual FX:     %.12f percentage points\n', ...
    maxDiff_spreadFX);


% Allow tiny numerical rounding error
tol_grouped = 1e-8;


if maxDiff_commVIX < tol_grouped

    fprintf('Commodity + VIX share is invariant across orderings.\n');

else

    warning( ...
        'Commodity + VIX combined FEVD differs across orderings.');

end


if maxDiff_spreadFX < tol_grouped

    fprintf('Spread + Residual FX share is invariant across orderings.\n');

else

    warning( ...
        'Spread + Residual FX combined FEVD differs across orderings.');

end

%% 20B. LONG-FORM COMBINED FEVD TABLE

FEVD_Grouped_Long = table();


for mm = 1:M

    for hh = 1:length(fevdHorizons)

        newRow = table( ...
            string(modelNames{mm}), ...
            fevdHorizons(hh), ...
            FEVD_comm_vix(mm,hh), ...
            FEVD_spread_fx(mm,hh), ...
            'VariableNames', ...
            { ...
            'Model', ...
            'Horizon', ...
            'CommodityPlusVIX', ...
            'SpreadPlusResidualFX'});

        FEVD_Grouped_Long = ...
            [FEVD_Grouped_Long; newRow];

    end

end


fprintf('\n');
fprintf('============================================================\n');
fprintf('COMBINED RTWI FEVD SHARES ACROSS ORDERINGS\n');
fprintf('============================================================\n');

disp(FEVD_Grouped_Long);

%% 20C. INVARIANT GROUPED FEVD TABLE
%
% Since the grouped contributions are invariant across A-D, use
% Model A's values as the representative numbers.
%
% "Other macro shocks" contains:
%   US GDP
%   Australian GDP
%   Australian inflation
%
% This column is included so the rows sum to 100.


other_macro = ...
    100 ...
    - commVIX_reference ...
    - spreadFX_reference;


FEVD_Grouped_Invariant = table( ...
    fevdHorizons(:), ...
    commVIX_reference(:), ...
    spreadFX_reference(:), ...
    other_macro(:), ...
    'VariableNames', ...
    { ...
    'Horizon', ...
    'CommodityPlusVIX', ...
    'SpreadPlusResidualFX', ...
    'OtherMacroShocks'});


% Check that each row sums to 100
groupedSum = ...
    FEVD_Grouped_Invariant.CommodityPlusVIX ...
    + FEVD_Grouped_Invariant.SpreadPlusResidualFX ...
    + FEVD_Grouped_Invariant.OtherMacroShocks;


assert( ...
    max(abs(groupedSum-100)) < 1e-8);


fprintf('\n');
fprintf('============================================================\n');
fprintf('ORDERING-INVARIANT GROUPED RTWI FEVD\n');
fprintf('============================================================\n');

disp(FEVD_Grouped_Invariant);

%% 20D. SELECTED HORIZONS - INVARIANT GROUPED FEVD

selectedGroupedH = [1 8 20];


keepGrouped = ...
    ismember( ...
    FEVD_Grouped_Invariant.Horizon, ...
    selectedGroupedH);


FEVD_Grouped_Selected = ...
    FEVD_Grouped_Invariant(keepGrouped,:);


fprintf('\n');
fprintf('============================================================\n');
fprintf('SELECTED ORDERING-INVARIANT FEVD HORIZONS\n');
fprintf('============================================================\n');

disp(FEVD_Grouped_Selected);

%% 21. EXPORT RESULTS TO EXCEL

outputFile = ...
    fullfile( ...
        resultDir, ...
        'svar_ordering_robustness.xlsx');


if isfile(outputFile)
    delete(outputFile);
end


writetable( ...
    OrderingTable, ...
    outputFile, ...
    'Sheet','orderings');


writetable( ...
    SummaryTable, ...
    outputFile, ...
    'Sheet','IRF_summary');


writetable( ...
    FEVD_Long, ...
    outputFile, ...
    'Sheet','FEVD_long');


writetable( ...
    FEVD_Selected, ...
    outputFile, ...
    'Sheet','FEVD_selected');


%% 22. SAVE MATLAB RESULTS

ordering_results = struct();


ordering_results.modelNames = ...
    modelNames;

ordering_results.modelShort = ...
    modelShort;

ordering_results.orderIdx = ...
    orderIdx;

ordering_results.results = ...
    results_order;

ordering_results.SummaryTable = ...
    SummaryTable;

ordering_results.FEVD_Long = ...
    FEVD_Long;

ordering_results.FEVD_Selected = ...
    FEVD_Selected;

ordering_results.rtwiIRF_comm = ...
    rtwiIRF_comm;

ordering_results.rtwiIRF_vix = ...
    rtwiIRF_vix;

ordering_results.rtwiIRF_spread = ...
    rtwiIRF_spread;

ordering_results.FEVD_comm = ...
    FEVD_comm;

ordering_results.FEVD_vix = ...
    FEVD_vix;

ordering_results.FEVD_spread = ...
    FEVD_spread;

ordering_results.FEVD_fx = ...
    FEVD_fx;

ordering_results.fevdHorizons = ...
    fevdHorizons;

ordering_results.yearlab = ...
    yearlab_svar;

ordering_results.p = ...
    p;

ordering_results.n_foreign = ...
    n_foreign;

ordering_results.FEVD_comm_vix = ...
    FEVD_comm_vix;

ordering_results.FEVD_spread_fx = ...
    FEVD_spread_fx;

ordering_results.FEVD_Grouped_Long = ...
    FEVD_Grouped_Long;

ordering_results.FEVD_Grouped_Invariant = ...
    FEVD_Grouped_Invariant;

ordering_results.FEVD_Grouped_Selected = ...
    FEVD_Grouped_Selected;

ordering_results.maxDiff_commVIX = ...
    maxDiff_commVIX;

ordering_results.maxDiff_spreadFX = ...
    maxDiff_spreadFX;


save( ...
    fullfile( ...
        resultDir, ...
        'svar_ordering_robustness.mat'), ...
    'ordering_results');


%% 23. FINAL SUMMARY

fprintf('\n');
fprintf('============================================================\n');
fprintf('ORDERING ROBUSTNESS COMPLETE\n');
fprintf('============================================================\n');


for mm = 1:M

    fprintf('\n%s\n',modelNames{mm});

    fprintf('Max root: %.4f\n', ...
        maxRoots(mm));

    fprintf('Commodity RTWI impact / peak: %.3f / %.3f\n', ...
        commImpact(mm), ...
        commPeak(mm));

    fprintf('VIX RTWI impact / peak: %.3f / %.3f\n', ...
        vixImpact(mm), ...
        vixPeak(mm));

    fprintf('Spread RTWI impact / peak: %.3f / %.3f\n', ...
        spreadImpact(mm), ...
        spreadPeak(mm));

end


fprintf('\nResults workbook:\n%s\n', ...
    outputFile);


fprintf('\nResults MAT file:\n%s\n', ...
    fullfile(resultDir, ...
    'svar_ordering_robustness.mat'));


%% ================================================================
% LOCAL FUNCTION
%% ================================================================

function response = normalizedShockResponse( ...
    phi, ...
    B, ...
    shockIndex, ...
    shockSize, ...
    hor)

% ================================================================
% NORMALIZED STRUCTURAL SHOCK RESPONSE
%
% Rescales one column of B so that the impact response of the shocked
% variable itself equals shockSize.
%
% Other structural shocks are irrelevant because only the selected
% shock column is extracted after IRFs are calculated.
%
% OUTPUT:
% response = N x (hor+1) matrix containing responses of all variables
%            to the selected normalized shock.
% ================================================================


    N = size(B,1);


    Bn = B;


    ownImpact = ...
        B(shockIndex,shockIndex);


    if abs(ownImpact) < 1e-12

        error( ...
            'Shock own-impact is effectively zero.');

    end


    Bn(:,shockIndex) = ...
        shockSize * ...
        B(:,shockIndex) ./ ...
        ownImpact;


    IRF = ...
        calculate_IRF_FEVD( ...
            phi, ...
            Bn, ...
            hor);


    IRF3 = ...
        reshape( ...
            IRF, ...
            N,N,hor+1);


    response = ...
        squeeze( ...
            IRF3(:,shockIndex,:));


    % Normalization check
    assert( ...
        abs(response(shockIndex,1)-shockSize) < 1e-8);

end