%% ================================================================
%  AUSTRALIAN DOLLAR DRIVERS - INITIAL SOE-BVAR
%
%  Purpose:
%    Validate bvar_soe.m before producing IRFs, FEVD or HD.
%
%  Variables:
%
%    1. US real GDP gap
%    2. Commodity prices
%    3. VIX
%    4. Australian real GDP gap
%    5. Trimmed mean inflation
%    6. AU-US 2-year yield spread
%    7. Real TWI
%
%  Sample: 1995Q1-2026Q2
%  BVAR lags: 2
%  Foreign block: first 3 variables
%
%% ================================================================

clear;
clc;
close all;


%% 1. PATHS

folder = fileparts(mfilename('fullpath'));

addpath(fullfile(folder,'_func'));


filePath = ...
    fullfile(folder,'data','data_collected.xlsx');


resultDir = ...
    fullfile(folder,'results');

if ~exist(resultDir,'dir')
    mkdir(resultDir);
end


assert(exist('bvar_soe','file') == 2, ...
    'bvar_soe.m not found.');

assert(exist('olsvar','file') == 2, ...
    'olsvar.m not found.');

assert(exist('olsvar_soe','file') == 2, ...
    'olsvar_soe.m not found.');


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


%% 4. MAKE OTHER VARIABLES NUMERIC

varNames = ...
    data.Properties.VariableNames;


for jj = 3:width(data)

    v = varNames{jj};

    if ~isnumeric(data.(v))

        data.(v) = ...
            str2double(string(data.(v)));

    end

end


%% 5. SAMPLE

sampleStart = ...
    datetime(1995,1,1);

sampleEnd = ...
    datetime(2026,4,1);


sample = ...
    data.quarter_start >= sampleStart & ...
    data.quarter_start <= sampleEnd;


D = ...
    data(sample,:);


T = ...
    height(D);


assert(T == 126, ...
    'Unexpected sample length.');


yr = ...
    year(D.quarter_start);

qtr = ...
    ceil(month(D.quarter_start)/3);


quarterlab = ...
    string(yr) + "Q" + string(qtr);


fprintf('\n============================================================\n');
fprintf('INITIAL SOE-BVAR\n');
fprintf('============================================================\n');

fprintf('Sample: %s to %s\n', ...
    char(quarterlab(1)), ...
    char(quarterlab(end)));

fprintf('T = %d\n',T);


%% 6. TRANSFORM VARIABLES
%
% IDENTICAL to the locked SVAR(2) benchmark.


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


%% 7. QUADRATIC GDP DETRENDING

tt = ...
    (1:T)';


Xtrend = [ ...
    ones(T,1) ...
    tt ...
    tt.^2];


% US GDP

b_us = ...
    Xtrend \ log_us_gdp;

us_gdp_gap = ...
    log_us_gdp - Xtrend*b_us;


% Australian GDP

b_au = ...
    Xtrend \ log_au_gdp;

au_gdp_gap = ...
    log_au_gdp - Xtrend*b_au;


%% 8. BVAR DATASET

y = [ ...
    us_gdp_gap ...
    log_comm ...
    log_vix ...
    au_gdp_gap ...
    trim_inf ...
    spread_2yr ...
    log_rtwi];


Variables = { ...
    'US Real GDP gap', ...
    'Commodity prices', ...
    'VIX', ...
    'Australian Real GDP gap', ...
    'Trimmed mean inflation', ...
    'AU-US 2yr spread', ...
    'Real TWI'};


N = ...
    size(y,2);


assert(N == 7);

assert(~any(isnan(y(:))));
assert(~any(isinf(y(:))));


%% 9. MODEL SETTINGS

p = 2;

n_foreign = 3;


%% 10. CLASSICAL SVAR(2) COMPARATOR
%
% This is NOT redoing our whole SVAR exercise.
%
% We only want its point-estimate persistence for comparison.


d = ...
    zeros(T,0);


[phi_ols,~,SIGMA_ols,~,~] = ...
    olsvar_soe( ...
        y, ...
        p, ...
        d, ...
        n_foreign);


Companion_ols = [ ...
    phi_ols(2:end,:)'; ...
    eye(N*(p-1)) zeros(N*(p-1),N)];


root_ols = ...
    max(abs(eig(Companion_ols)));


fprintf('\nClassical SVAR(2) max root = %.4f\n', ...
    root_ols);

%% ================================================================
% FINAL BASELINE SOE-BVAR
%% ================================================================

options = struct();

% MCMC
options.ndraws = 10000;
options.burnin = 5000;
options.thin   = 1;

% Minnesota prior
options.lambda = 0.20;
options.decay  = 1;

options.own_lag_prior_mean = [ ...
    0
    1
    0
    0
    0
    0
    1];

% Intercept
options.intercept_var = 1e6;

% Covariance prior
options.sigma_df = N + 2;
options.sigma_scale_mult = 1;

% Maintain a stable VAR posterior
options.stable_only = true;
options.max_root = 0.9999;
options.max_stability_tries = 5000;

% We NEED residuals later for historical decomposition
options.store_residuals = true;

% Reproducibility
options.seed = 12345;

options.verbose = true;


%% ESTIMATE

tic;

BVAR = ...
    bvar_soe( ...
        y, ...
        p, ...
        n_foreign, ...
        options);

elapsed = toc;


fprintf('\nFinal BVAR elapsed time: %.2f seconds\n',elapsed);


%% BASIC DIAGNOSTICS

fprintf('\n============================================================\n');
fprintf('FINAL BVAR DIAGNOSTICS\n');
fprintf('============================================================\n');

fprintf('Posterior mean root:       %.4f\n', ...
    BVAR.root_mean_phi);

fprintf('Posterior median root:     %.4f\n', ...
    BVAR.root_median_phi);

fprintf('Median posterior root:     %.4f\n', ...
    median(BVAR.root_draws));

fprintf('95th percentile root:      %.4f\n', ...
    quantile(BVAR.root_draws,0.95));

fprintf('99th percentile root:      %.4f\n', ...
    quantile(BVAR.root_draws,0.99));

fprintf('Maximum retained root:     %.4f\n', ...
    max(BVAR.root_draws));

fprintf('Stability rejection rate:  %.2f%%\n', ...
    100*BVAR.info.stability_rejection_rate);

fprintf('Max forbidden coefficient: %.3e\n', ...
    BVAR.info.maxForbiddenCoefficient);


%% SAVE

save( ...
    fullfile( ...
        resultDir, ...
        'bvar_soe_baseline_lambda020_stable.mat'), ...
    'BVAR', ...
    'Variables', ...
    '-v7.3');

figure('Color','w','Position',[100 100 1100 450]);

plot(BVAR.root_draws,'k');

yline(1,'r:');

xlabel('Posterior draw');
ylabel('Maximum companion root');

title('BVAR Posterior Root Trace');

grid on;
box off;

N = BVAR.N;

row_rtwi_lag1 = 1 + 7;
row_comm_lag1 = 1 + 2;

draw_rtwi_own1 = ...
    squeeze(BVAR.phi_draws(row_rtwi_lag1,7,:));

draw_comm_own1 = ...
    squeeze(BVAR.phi_draws(row_comm_lag1,2,:));


figure('Color','w','Position',[100 100 1100 450]);

tiledlayout(1,2,'TileSpacing','compact');

nexttile;

plot(draw_rtwi_own1,'k');

title('RTWI own first lag');
xlabel('Posterior draw');
grid on;
box off;


nexttile;

plot(draw_comm_own1,'k');

title('Commodity-price own first lag');
xlabel('Posterior draw');
grid on;
box off;
