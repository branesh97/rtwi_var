%% ================================================================
%  AUSTRALIAN DOLLAR DRIVERS - INITIAL SVAR
%
%  Question:
%  Commodity prices, relative interest rates or global risk?
%
%  Sample: 1995Q1 - 2026Q2
%
%  Recursive ordering:
%
%  FOREIGN BLOCK
%    1. US real GDP gap
%    2. RBA commodity price index (SDR)
%    3. VIX
%
%  DOMESTIC / AUSTRALIAN BLOCK
%    4. Australian real GDP gap
%    5. Australian trimmed mean inflation
%    6. AU-US 2-year yield spread
%    7. Australian real TWI
%
%  Small-open-economy restriction:
%    Australian variables do not affect foreign variables
%    contemporaneously or with lags.
%
%  Identification:
%    Recursive Cholesky identification.
%
%  Initial estimation:
%    Point estimates, IRFs, stability diagnostics and FEVD.
%
%  No bootstrap confidence intervals yet.
%% ================================================================

clear;
clc;
close all;


%% 1. PRELIMINARY

% Folder containing this script
folder = fileparts(mfilename('fullpath'));

% Add functions folder
addpath(fullfile(folder,'_func'));


% Data file
filePath = fullfile(folder,'data','data_collected.xlsx');

% Output folders
figDir = fullfile(folder,'figures');

if ~exist(figDir,'dir')
    mkdir(figDir);
end

resultDir = fullfile(folder,'results');

if ~exist(resultDir,'dir')
    mkdir(resultDir);
end


% Check required functions are available
assert(exist('olsvar_soe','file') == 2, ...
    'olsvar_soe.m not found in MATLAB path.');

assert(exist('calculate_IRF_FEVD','file') == 2, ...
    'calculate_IRF_FEVD.m not found in MATLAB path.');


%% 2. IMPORT DATA

data = readtable( ...
    filePath, ...
    'Sheet','data', ...
    'VariableNamingRule','preserve');


% Convert common text missing-value indicators
data = standardizeMissing( ...
    data, ...
    {'NA','N/A','na',''});


%% 3. MAKE SURE DATES ARE DATETIME

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

            data.(v) = datetime(data.(v));

        end

    end

end


%% 4. MAKE SURE NON-DATE VARIABLES ARE NUMERIC

varNames = data.Properties.VariableNames;


for jj = 3:width(data)

    v = varNames{jj};

    if ~isnumeric(data.(v))

        data.(v) = ...
            str2double(string(data.(v)));

    end

end


%% 5. YEARLAB

yr = year(data.quarter_start);

qtr = ceil( ...
    month(data.quarter_start)/3);


% Same convention as replication:
%
% 1995Q1 = 1995.00
% 1995Q2 = 1995.25
% 1995Q3 = 1995.50
% 1995Q4 = 1995.75

yearlab = ...
    yr + (qtr-1)/4;


quarterlab = ...
    string(yr) + "Q" + string(qtr);


%% 6. SELECT SVAR SAMPLE

sampleStart = datetime(1995,1,1);
sampleEnd   = datetime(2026,4,1);   % 2026Q2


sample = ...
    data.quarter_start >= sampleStart & ...
    data.quarter_start <= sampleEnd;


D = data(sample,:);

yearlab_svar = yearlab(sample);
quarterlab_svar = quarterlab(sample);


T = height(D);


fprintf('\n============================================================\n');
fprintf('INITIAL AUSTRALIAN DOLLAR SVAR\n');
fprintf('============================================================\n');

fprintf('Sample: %s to %s\n', ...
    char(quarterlab_svar(1)), ...
    char(quarterlab_svar(end)));

fprintf('Observations: %d\n',T);


% 1995Q1 to 2026Q2 should contain 126 observations
assert(T == 126, ...
    'Unexpected sample length.');



%% 7. CHECK VARIABLES REQUIRED FOR THE SVAR
%
% Required raw variables:
%
% us_rgdp       US real GDP
% comm_price    RBA commodity price index, SDR
% vix           CBOE VIX
% au_rgdp       Australian real GDP
% au_inf_trim   quarterly trimmed mean inflation
% au_us_2yr     AU-US 2-year government yield spread
% rtwi          Australian real TWI


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
        'Variable %s not found in data sheet.',v);

    assert( ...
        all(isfinite(D.(v))), ...
        'Variable %s contains missing observations in SVAR sample.',v);

end


%% 8. TRANSFORM VARIABLES
%
% Following the spirit of Manalo et al.:
%
% GDP:
%   100 * log level, then quadratic detrending
%
% Commodity prices:
%   100 * log level
%
% VIX:
%   100 * log level
%
% Inflation:
%   quarterly percentage change, already in data
%
% AU-US 2-year spread:
%   level, percentage points
%
% Real TWI:
%   100 * log level


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



%% 9. QUADRATIC DETRENDING OF GDP
%
% The quadratic trends are estimated over the actual SVAR sample:
% 1995Q1-2026Q2.
%
% This follows the approach used in our Manalo replication.


tt = (1:T)';

Xtrend = [ ...
    ones(T,1) ...
    tt ...
    tt.^2];


% ---------------------------------------------------------------
% US GDP
% ---------------------------------------------------------------

b_us = ...
    Xtrend \ log_us_gdp;

trend_us = ...
    Xtrend*b_us;

us_gdp_gap = ...
    log_us_gdp - trend_us;


% ---------------------------------------------------------------
% Australian GDP
% ---------------------------------------------------------------

b_au = ...
    Xtrend \ log_au_gdp;

trend_au = ...
    Xtrend*b_au;

au_gdp_gap = ...
    log_au_gdp - trend_au;



%% 10. CONSTRUCT VAR DATASET
%
% Recursive ordering:
%
% 1 US GDP
% 2 Commodity prices
% 3 VIX
% 4 Australian GDP
% 5 Inflation
% 6 AU-US 2-year yield spread
% 7 Real TWI


y = [ ...
    us_gdp_gap ...
    log_comm ...
    log_vix ...
    au_gdp_gap ...
    trim_inf ...
    spread_2yr ...
    log_rtwi];


Variables = { ...
    'US Real GDP', ...
    'Commodity Prices', ...
    'VIX', ...
    'Australian Real GDP', ...
    'Trimmed Mean Inflation', ...
    'AU-US 2yr Spread', ...
    'Real TWI'};


N = size(y,2);


assert(N == 7);
assert(~any(isnan(y(:))));
assert(~any(isinf(y(:))));


%% 11. MODEL SETTINGS

% Same lag length as Manalo et al.
p = 2;


% First three variables are treated as foreign/external
n_foreign = 3;


% Structural shock indexes
shock_us     = 1;
shock_comm   = 2;
shock_vix    = 3;
shock_augdp  = 4;
shock_inf    = 5;
shock_spread = 6;
shock_er     = 7;


% IRF horizon
hor = 24;


% FEVD horizon
hor_fevd = 40;


%% 12. DETERMINISTIC CONTROLS
%
% None in the INITIAL specification.
%
% Reasons:
%
% 1. Inflation targeting began before the 1995 sample, so an
%    inflation-targeting dummy would simply duplicate the constant.
%
% 2. We do not initially include GFC / pandemic pulse dummies because
%    VIX and commodity prices are themselves intended to capture the
%    large global shocks occurring during those periods.
%
% Crisis controls can be added later as robustness checks.


d = [];


%% 13. ESTIMATE REDUCED-FORM VAR WITH SOE RESTRICTIONS

[phi,gamma,SIGMA,X,e] = ...
    olsvar_soe( ...
        y, ...
        p, ...
        d, ...
        n_foreign);


fprintf('\nVAR estimated successfully.\n');

fprintf('Number of endogenous variables: %d\n',N);
fprintf('Lag order: %d\n',p);
fprintf('Foreign-block variables: %d\n',n_foreign);



%% 14. VAR STABILITY

Companion = [ ...
    phi(2:end,:)'; ...
    eye(N*(p-1)) zeros(N*(p-1),N)];


roots_VAR = ...
    eig(Companion);


max_root = ...
    max(abs(roots_VAR));


fprintf('\n============================================================\n');
fprintf('VAR STABILITY\n');
fprintf('============================================================\n');

fprintf('Maximum companion root: %.4f\n', ...
    max_root);


if max_root < 1

    fprintf('VAR is stable.\n');

else

    fprintf('WARNING: VAR is not stable.\n');

end



%% 15. REDUCED-FORM RESIDUAL COVARIANCE MATRIX

SIGMA_table = ...
    array2table( ...
        SIGMA, ...
        'VariableNames', ...
        matlab.lang.makeValidName(Variables), ...
        'RowNames', ...
        Variables);


fprintf('\n============================================================\n');
fprintf('REDUCED-FORM RESIDUAL COVARIANCE MATRIX\n');
fprintf('============================================================\n');

disp(SIGMA_table);



%% 16. CHOLESKY IDENTIFICATION
%
% Structural form:
%
% e_t = B * epsilon_t
%
% With the ordering:
%
% US GDP
% -> Commodity prices
% -> VIX
% -> Australian GDP
% -> Inflation
% -> 2-year spread
% -> RTWI


[~,cholFlag] = chol(SIGMA);


assert( ...
    cholFlag == 0, ...
    'SIGMA is not positive definite; Cholesky identification failed.');


B = ...
    chol(SIGMA,'lower');


B_table = ...
    array2table( ...
        B, ...
        'VariableNames', ...
        matlab.lang.makeValidName(Variables), ...
        'RowNames', ...
        Variables);


fprintf('\n============================================================\n');
fprintf('CHOLESKY IMPACT MATRIX B\n');
fprintf('============================================================\n');

disp(B_table);



%% 17. ONE-STANDARD-DEVIATION STRUCTURAL IRFs
%
% These use the raw Cholesky B matrix.
%
% Keep these for diagnostics and FEVD interpretation.


IRF_raw = ...
    calculate_IRF_FEVD( ...
        phi, ...
        B, ...
        hor);


% Reshape:
%
% dimension 1 = response variable
% dimension 2 = structural shock
% dimension 3 = horizon

IRF_raw_3d = ...
    reshape( ...
        IRF_raw, ...
        N,N,hor+1);



%% 18. NORMALISED HEADLINE SHOCKS
%
% For presentation:
%
% Commodity shock:
%     +10 log points in commodity prices
%     approximately a 10 percent increase
%
% VIX shock:
%     +10 log points in VIX
%     approximately a 10 percent increase
%
% Relative-yield shock:
%     +1 percentage point = +100 basis points
%     in AU-US 2-year spread
%
% Exchange-rate shock:
%     +10 log points in RTWI
%     approximately a 10 percent appreciation
%
% This uses the same 10-log-point convention as our Manalo replication.


size_comm_shock = 10;
size_vix_shock = 10;
size_spread_shock = 1;
size_er_shock = 10;



%% 18A. COMMODITY-PRICE SHOCK

B_comm = B;

B_comm(:,shock_comm) = ...
    size_comm_shock * ...
    B(:,shock_comm) ./ ...
    B(shock_comm,shock_comm);


IRF_comm = ...
    calculate_IRF_FEVD( ...
        phi, ...
        B_comm, ...
        hor);


IRF_comm_3d = ...
    reshape( ...
        IRF_comm, ...
        N,N,hor+1);


resp_comm = ...
    squeeze( ...
        IRF_comm_3d(:,shock_comm,:));


% Check normalization
assert( ...
    abs(resp_comm(shock_comm,1) - size_comm_shock) < 1e-8);



%% 18B. VIX / GLOBAL-RISK SHOCK

B_vix = B;

B_vix(:,shock_vix) = ...
    size_vix_shock * ...
    B(:,shock_vix) ./ ...
    B(shock_vix,shock_vix);


IRF_vix = ...
    calculate_IRF_FEVD( ...
        phi, ...
        B_vix, ...
        hor);


IRF_vix_3d = ...
    reshape( ...
        IRF_vix, ...
        N,N,hor+1);


resp_vix = ...
    squeeze( ...
        IRF_vix_3d(:,shock_vix,:));


assert( ...
    abs(resp_vix(shock_vix,1) - size_vix_shock) < 1e-8);



%% 18C. AU-US 2-YEAR YIELD-SPREAD SHOCK

B_spread = B;

B_spread(:,shock_spread) = ...
    size_spread_shock * ...
    B(:,shock_spread) ./ ...
    B(shock_spread,shock_spread);


IRF_spread = ...
    calculate_IRF_FEVD( ...
        phi, ...
        B_spread, ...
        hor);


IRF_spread_3d = ...
    reshape( ...
        IRF_spread, ...
        N,N,hor+1);


resp_spread = ...
    squeeze( ...
        IRF_spread_3d(:,shock_spread,:));


assert( ...
    abs(resp_spread(shock_spread,1) - size_spread_shock) < 1e-8);



%% 18D. EXCHANGE-RATE SHOCK
%
% Useful for checking continuity with the Manalo framework.

B_er = B;

B_er(:,shock_er) = ...
    size_er_shock * ...
    B(:,shock_er) ./ ...
    B(shock_er,shock_er);


IRF_er = ...
    calculate_IRF_FEVD( ...
        phi, ...
        B_er, ...
        hor);


IRF_er_3d = ...
    reshape( ...
        IRF_er, ...
        N,N,hor+1);


resp_er = ...
    squeeze( ...
        IRF_er_3d(:,shock_er,:));


assert( ...
    abs(resp_er(shock_er,1) - size_er_shock) < 1e-8);



%% 19. HEADLINE RTWI RESPONSES
%
% This is the first figure relevant to the article.
%
% RTWI is in 100*log units:
% response is approximately percentage change.


h = 0:hor;


rtwi_comm = ...
    resp_comm(shock_er,:);

rtwi_vix = ...
    resp_vix(shock_er,:);

rtwi_spread = ...
    resp_spread(shock_er,:);


figure( ...
    'Color','w', ...
    'Position',[100 100 1100 360]);


tiledlayout( ...
    1,3, ...
    'TileSpacing','compact', ...
    'Padding','compact');


% ---------------------------------------------------------------
% Commodity shock
% ---------------------------------------------------------------

nexttile;

plot( ...
    h, ...
    rtwi_comm, ...
    '-k', ...
    'LineWidth',2);

hold on;

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


% ---------------------------------------------------------------
% VIX shock
% ---------------------------------------------------------------

nexttile;

plot( ...
    h, ...
    rtwi_vix, ...
    '-k', ...
    'LineWidth',2);

hold on;

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


% ---------------------------------------------------------------
% Relative-yield shock
% ---------------------------------------------------------------

nexttile;

plot( ...
    h, ...
    rtwi_spread, ...
    '-k', ...
    'LineWidth',2);

hold on;

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
    'Real TWI Responses to Commodity, Risk and Relative-Yield Shocks');


exportgraphics( ...
    gcf, ...
    fullfile(figDir,'09_svar_rtwi_headline_irfs.png'), ...
    'Resolution',300);



%% 20. IMPACT AND PEAK RTWI RESPONSES

fprintf('\n============================================================\n');
fprintf('HEADLINE RTWI RESPONSES\n');
fprintf('============================================================\n');


fprintf('\nCommodity-price shock (+10%%):\n');
fprintf('Impact RTWI response: %.3f%%\n', ...
    rtwi_comm(1));

[comm_max_abs,comm_ind] = ...
    max(abs(rtwi_comm));

fprintf('Largest absolute RTWI response: %.3f%% at horizon %d\n', ...
    rtwi_comm(comm_ind), ...
    comm_ind-1);


fprintf('\nVIX shock (+10%%):\n');
fprintf('Impact RTWI response: %.3f%%\n', ...
    rtwi_vix(1));

[vix_max_abs,vix_ind] = ...
    max(abs(rtwi_vix));

fprintf('Largest absolute RTWI response: %.3f%% at horizon %d\n', ...
    rtwi_vix(vix_ind), ...
    vix_ind-1);


fprintf('\nAU-US 2yr spread shock (+100bp):\n');
fprintf('Impact RTWI response: %.3f%%\n', ...
    rtwi_spread(1));

[spread_max_abs,spread_ind] = ...
    max(abs(rtwi_spread));

fprintf('Largest absolute RTWI response: %.3f%% at horizon %d\n', ...
    rtwi_spread(spread_ind), ...
    spread_ind-1);



%% 21. FULL-SYSTEM IRFs TO COMMODITY SHOCK

figure( ...
    'Color','w', ...
    'Position',[100 50 1100 750]);


tiledlayout( ...
    2,4, ...
    'TileSpacing','compact', ...
    'Padding','compact');


for ii = 1:N

    nexttile;

    plot( ...
        h, ...
        resp_comm(ii,:), ...
        '-k', ...
        'LineWidth',1.8);

    hold on;

    yline( ...
        0, ...
        'k:', ...
        'HandleVisibility','off');

    grid on;
    box off;

    title(Variables{ii});

    xlabel('Quarters');

    xlim([0 hor]);

end


sgtitle('Responses to a +10% Commodity-Price Shock');


exportgraphics( ...
    gcf, ...
    fullfile(figDir,'10_svar_commodity_shock_full.png'), ...
    'Resolution',300);



%% 22. FULL-SYSTEM IRFs TO VIX SHOCK

figure( ...
    'Color','w', ...
    'Position',[100 50 1100 750]);


tiledlayout( ...
    2,4, ...
    'TileSpacing','compact', ...
    'Padding','compact');


for ii = 1:N

    nexttile;

    plot( ...
        h, ...
        resp_vix(ii,:), ...
        '-k', ...
        'LineWidth',1.8);

    hold on;

    yline( ...
        0, ...
        'k:', ...
        'HandleVisibility','off');

    grid on;
    box off;

    title(Variables{ii});

    xlabel('Quarters');

    xlim([0 hor]);

end


sgtitle('Responses to a +10% VIX Shock');


exportgraphics( ...
    gcf, ...
    fullfile(figDir,'11_svar_vix_shock_full.png'), ...
    'Resolution',300);



%% 23. FULL-SYSTEM IRFs TO RELATIVE-YIELD SHOCK

figure( ...
    'Color','w', ...
    'Position',[100 50 1100 750]);


tiledlayout( ...
    2,4, ...
    'TileSpacing','compact', ...
    'Padding','compact');


for ii = 1:N

    nexttile;

    plot( ...
        h, ...
        resp_spread(ii,:), ...
        '-k', ...
        'LineWidth',1.8);

    hold on;

    yline( ...
        0, ...
        'k:', ...
        'HandleVisibility','off');

    grid on;
    box off;

    title(Variables{ii});

    xlabel('Quarters');

    xlim([0 hor]);

end


sgtitle('Responses to a +100 bp AU-US 2-Year Yield-Spread Shock');


exportgraphics( ...
    gcf, ...
    fullfile(figDir,'12_svar_spread_shock_full.png'), ...
    'Resolution',300);



%% 24. FORECAST-ERROR VARIANCE DECOMPOSITION
%
% IMPORTANT:
%
% FEVD must use the UNNORMALISED Cholesky matrix B.
%
% Do not use B_comm, B_vix or B_spread here because rescaling individual
% structural shocks would artificially alter their relative variances.


[~,FEVD] = ...
    calculate_IRF_FEVD( ...
        phi, ...
        B, ...
        hor_fevd, ...
        'FEVD');



%% 25. RTWI FEVD
%
% Contribution of each structural shock to the forecast-error variance
% of the Real TWI.


fevdHorizons = [ ...
    1 ...
    4 ...
    8 ...
    12 ...
    20 ...
    40];


rtwi_fevd = ...
    squeeze( ...
        FEVD( ...
            shock_er, ...
            :, ...
            fevdHorizons));


% squeeze gives N x H
assert( ...
    size(rtwi_fevd,1) == N);


% Verify each horizon sums to approximately 100
assert( ...
    max(abs(sum(rtwi_fevd,1)-100)) < 1e-8);


FEVD_RTWI_Table = ...
    array2table( ...
        rtwi_fevd, ...
        'VariableNames', ...
        {'H1','H4','H8','H12','H20','H40'}, ...
        'RowNames', ...
        Variables);


fprintf('\n============================================================\n');
fprintf('REAL TWI FORECAST-ERROR VARIANCE DECOMPOSITION\n');
fprintf('============================================================\n');

disp(FEVD_RTWI_Table);



%% 26. COMPACT FEVD OF THE THREE HEADLINE CHANNELS
%
% The rows do NOT necessarily sum to 100 because we separately retain
% US GDP, Australian GDP, inflation and the residual exchange-rate shock.


headline_fevd = [ ...
    rtwi_fevd(shock_comm,:); ...
    rtwi_fevd(shock_vix,:); ...
    rtwi_fevd(shock_spread,:); ...
    rtwi_fevd(shock_er,:)];


FEVD_Headline_Table = ...
    array2table( ...
        headline_fevd, ...
        'VariableNames', ...
        {'H1','H4','H8','H12','H20','H40'}, ...
        'RowNames', ...
        { ...
        'CommodityPrices', ...
        'VIX', ...
        'AU_US_2yrSpread', ...
        'ResidualExchangeRateShock'});


fprintf('\n============================================================\n');
fprintf('HEADLINE CONTRIBUTORS TO REAL TWI VARIANCE\n');
fprintf('============================================================\n');

disp(FEVD_Headline_Table);



%% 27. GROUPED RTWI FEVD
%
% Useful as a broad diagnostic:
%
% Global/external block:
%   US GDP + commodity prices + VIX
%
% Australian macro:
%   Australian GDP + inflation
%
% Relative rates:
%   AU-US 2-year spread
%
% Residual exchange-rate shock:
%   Real TWI shock


fevd_global = ...
    sum( ...
        rtwi_fevd(1:3,:), ...
        1);


fevd_au_macro = ...
    sum( ...
        rtwi_fevd(4:5,:), ...
        1);


fevd_relative_rates = ...
    rtwi_fevd(6,:);


fevd_exchange_residual = ...
    rtwi_fevd(7,:);


grouped_fevd = [ ...
    fevd_global; ...
    fevd_au_macro; ...
    fevd_relative_rates; ...
    fevd_exchange_residual];


assert( ...
    max(abs(sum(grouped_fevd,1)-100)) < 1e-8);


FEVD_Grouped_Table = ...
    array2table( ...
        grouped_fevd, ...
        'VariableNames', ...
        {'H1','H4','H8','H12','H20','H40'}, ...
        'RowNames', ...
        { ...
        'GlobalExternal', ...
        'AustralianMacro', ...
        'RelativeRates', ...
        'ResidualExchangeRateShock'});


fprintf('\n============================================================\n');
fprintf('GROUPED REAL TWI FEVD\n');
fprintf('============================================================\n');

disp(FEVD_Grouped_Table);



%% 28. EXPORT FEVD TABLES

fevdFile = ...
    fullfile( ...
        resultDir, ...
        'svar_initial_fevd.xlsx');


if isfile(fevdFile)
    delete(fevdFile);
end


writetable( ...
    FEVD_RTWI_Table, ...
    fevdFile, ...
    'Sheet','RTWI_full', ...
    'WriteRowNames',true);


writetable( ...
    FEVD_Headline_Table, ...
    fevdFile, ...
    'Sheet','RTWI_headline', ...
    'WriteRowNames',true);


writetable( ...
    FEVD_Grouped_Table, ...
    fevdFile, ...
    'Sheet','RTWI_grouped', ...
    'WriteRowNames',true);



%% 29. SAVE INITIAL SVAR RESULTS

results_svar = struct();


% ---------------------------------------------------------------
% Model information
% ---------------------------------------------------------------

results_svar.sample_start = 1995;
results_svar.sample_end = 2026 + 1/4;

results_svar.p = p;
results_svar.n_foreign = n_foreign;

results_svar.Variables = Variables;

results_svar.yearlab = yearlab_svar;

results_svar.y = y;


% ---------------------------------------------------------------
% Reduced-form estimates
% ---------------------------------------------------------------

results_svar.phi = phi;
results_svar.gamma = gamma;
results_svar.SIGMA = SIGMA;
results_svar.residuals = e;

results_svar.max_root = max_root;


% ---------------------------------------------------------------
% Structural identification
% ---------------------------------------------------------------

results_svar.B = B;


% ---------------------------------------------------------------
% Normalised IRFs
% ---------------------------------------------------------------

results_svar.irf_commodity = resp_comm;
results_svar.irf_vix = resp_vix;
results_svar.irf_spread = resp_spread;
results_svar.irf_exchange_rate = resp_er;


% ---------------------------------------------------------------
% RTWI headline responses
% ---------------------------------------------------------------

results_svar.rtwi_commodity = rtwi_comm;
results_svar.rtwi_vix = rtwi_vix;
results_svar.rtwi_spread = rtwi_spread;


% ---------------------------------------------------------------
% FEVD
% ---------------------------------------------------------------

results_svar.FEVD = FEVD;

results_svar.rtwi_fevd = rtwi_fevd;
results_svar.grouped_fevd = grouped_fevd;


% ---------------------------------------------------------------
% Trends
% ---------------------------------------------------------------

results_svar.us_gdp_trend = trend_us;
results_svar.au_gdp_trend = trend_au;


save( ...
    fullfile( ...
        resultDir, ...
        'svar_initial.mat'), ...
    'results_svar');



%% 30. FINAL DIAGNOSTIC SUMMARY

fprintf('\n============================================================\n');
fprintf('INITIAL SVAR COMPLETE\n');
fprintf('============================================================\n');

fprintf('Sample: %s to %s\n', ...
    char(quarterlab_svar(1)), ...
    char(quarterlab_svar(end)));

fprintf('T = %d\n',T);

fprintf('N = %d\n',N);

fprintf('p = %d\n',p);

fprintf('Maximum VAR root = %.4f\n', ...
    max_root);

fprintf('\nResults saved to:\n%s\n', ...
    fullfile(resultDir,'svar_initial.mat'));

fprintf('\nFEVD tables saved to:\n%s\n', ...
    fevdFile);