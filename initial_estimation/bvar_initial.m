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


%% 11. BVAR SMOKE-TEST SETTINGS
%
% Start SMALL.
%
% Do not use 5000 draws until this has passed.

options = struct();


options.ndraws = 200;

options.burnin = 200;

options.thin = 1;


% Minnesota prior

options.lambda = 0.20;

options.decay = 1;

options.rw_threshold = 0.80;


% Diffuse intercept prior

options.intercept_var = 1e6;


% Covariance prior

options.sigma_df = ...
    N + 2;

options.sigma_scale_mult = ...
    1;


% IMPORTANT:
%
% Start WITHOUT truncating the posterior to stable draws.
%
% We first want to see the natural posterior root distribution.

options.stable_only = false;

options.max_root = 0.9999;


% Reproducibility

options.seed = 12345;


options.store_residuals = true;

options.verbose = true;

% Explicit Minnesota prior means for own first lags:
%
% 1. US GDP gap          0
% 2. Commodity prices    1
% 3. VIX                 0
% 4. Australian GDP gap  0
% 5. Inflation           0
% 6. AU-US 2yr spread    0
% 7. Real TWI            1

options.own_lag_prior_mean = [ ...
    0
    1
    0
    0
    0
    0
    1];


%% 12. ESTIMATE SOE-BVAR

tic;


BVAR_test = ...
    bvar_soe( ...
        y, ...
        p, ...
        n_foreign, ...
        options);


elapsed = ...
    toc;


fprintf('\nSmoke-test elapsed time: %.1f seconds\n', ...
    elapsed);


%% 13. PRIOR DIAGNOSTICS

PriorCheck = table( ...
    string(Variables(:)), ...
    BVAR_test.prior.ar1, ...
    BVAR_test.prior.own_lag_prior_mean, ...
    BVAR_test.prior.sigma2, ...
    'VariableNames', ...
    { ...
    'Variable', ...
    'AR1', ...
    'OwnLagPriorMean', ...
    'ARResidualVariance'});


fprintf('\n============================================================\n');
fprintf('MINNESOTA PRIOR CALIBRATION\n');
fprintf('============================================================\n');

disp(PriorCheck);


%% 14. SOE RESTRICTION CHECK

fprintf('\n============================================================\n');
fprintf('SOE RESTRICTION CHECK\n');
fprintf('============================================================\n');


fprintf('Maximum forbidden coefficient = %.12g\n', ...
    BVAR_test.info.maxForbiddenCoefficient);


assert( ...
    BVAR_test.info.maxForbiddenCoefficient < 1e-14, ...
    'SOE zero restrictions failed.');


%% 15. POSTERIOR ROOT DIAGNOSTICS

rootDraws = ...
    BVAR_test.root_draws;


RootSummary = table( ...
    root_ols, ...
    BVAR_test.root_mean_phi, ...
    BVAR_test.root_median_phi, ...
    median(rootDraws), ...
    quantile(rootDraws,0.70), ...
    quantile(rootDraws,0.90), ...
    quantile(rootDraws,0.95), ...
    quantile(rootDraws,0.99), ...
    max(rootDraws), ...
    mean(rootDraws >= 1)*100, ...
    'VariableNames', ...
    { ...
    'ClassicalSVARRoot', ...
    'PosteriorMeanPhiRoot', ...
    'PosteriorMedianPhiRoot', ...
    'MedianDrawRoot', ...
    'P70DrawRoot', ...
    'P90DrawRoot', ...
    'P95DrawRoot', ...
    'P99DrawRoot', ...
    'MaximumDrawRoot', ...
    'PercentUnstableDraws'});


fprintf('\n============================================================\n');
fprintf('POSTERIOR PERSISTENCE\n');
fprintf('============================================================\n');

disp(RootSummary);


%% 16. ROOT HISTOGRAM

figure( ...
    'Color','w', ...
    'Position',[150 150 800 450]);


histogram( ...
    rootDraws, ...
    25);


hold on;


xline( ...
    1, ...
    '-k', ...
    'Unit root', ...
    'LineWidth',1.5);


xline( ...
    root_ols, ...
    '--k', ...
    'Classical SVAR', ...
    'LineWidth',1.2);


grid on;
box off;


xlabel('Maximum companion root');

ylabel('Posterior draws');

title('Persistence in the Initial SOE-BVAR');


%% 17. COMPARE POSTERIOR MEAN COEFFICIENT ROOT
%
% This is useful for seeing whether Minnesota shrinkage reduces
% persistence relative to the classical VAR.


fprintf('\n============================================================\n');
fprintf('INITIAL BVAR COMPARISON\n');
fprintf('============================================================\n');


fprintf('Classical SVAR root:        %.4f\n', ...
    root_ols);


fprintf('BVAR posterior-mean root:   %.4f\n', ...
    BVAR_test.root_mean_phi);


fprintf('BVAR posterior-median root: %.4f\n', ...
    BVAR_test.root_median_phi);


%% 18. SAVE SMOKE-TEST RESULTS

save( ...
    fullfile( ...
        resultDir, ...
        'bvar_soe_smoke_test.mat'), ...
    'BVAR_test', ...
    'PriorCheck', ...
    'RootSummary', ...
    'Variables', ...
    '-v7.3');


fprintf('\n============================================================\n');
fprintf('SMOKE TEST COMPLETE\n');
fprintf('============================================================\n');

%% ================================================================
%  BVAR MINNESOTA TIGHTNESS SENSITIVITY
%
%  Hold fixed:
%    - p = 2
%    - SOE restriction
%    - sample
%    - transformations
%    - prior means
%
%  Vary:
%    lambda = 0.10, 0.20, 0.30
%
%  IMPORTANT:
%    stable_only = false
%
%  Purpose:
%    See how prior tightness affects persistence and the unstable
%    posterior tail before selecting the final BVAR specification.
%% ================================================================

lambdaGrid = [0.10 0.20 0.30];

nLambda = ...
    length(lambdaGrid);


%% STORAGE

MeanPhiRoot = ...
    nan(nLambda,1);

MedianPhiRoot = ...
    nan(nLambda,1);

MedianDrawRoot = ...
    nan(nLambda,1);

P70Root = ...
    nan(nLambda,1);

P90Root = ...
    nan(nLambda,1);

P95Root = ...
    nan(nLambda,1);

P99Root = ...
    nan(nLambda,1);

MaxRoot = ...
    nan(nLambda,1);

PercentUnstable = ...
    nan(nLambda,1);


BVAR_lambda = ...
    cell(nLambda,1);


%% RUN EACH LAMBDA

for ll = 1:nLambda

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('LAMBDA = %.2f\n',lambdaGrid(ll));
    fprintf('============================================================\n');


    options = struct();


    % Enough draws for useful sensitivity diagnostics.
    % Still much lighter than our eventual final BVAR.

    options.ndraws = 1000;

    options.burnin = 1000;

    options.thin = 1;


    %% MINNESOTA PRIOR

    options.lambda = ...
        lambdaGrid(ll);

    options.decay = ...
        1;


    % Economically specified own-first-lag prior means:
    %
    % 1 US GDP gap          -> 0
    % 2 Commodity prices    -> 1
    % 3 VIX                 -> 0
    % 4 AU GDP gap          -> 0
    % 5 Inflation           -> 0
    % 6 AU-US 2yr spread    -> 0
    % 7 Real TWI            -> 1

    options.own_lag_prior_mean = [ ...
        0
        1
        0
        0
        0
        0
        1];


    options.intercept_var = ...
        1e6;


    %% SIGMA PRIOR

    options.sigma_df = ...
        N + 2;

    options.sigma_scale_mult = ...
        1;


    %% DO NOT IMPOSE STABILITY YET

    options.stable_only = ...
        false;

    options.max_root = ...
        0.9999;


    %% OTHER SETTINGS

    % Different reproducible stream for each lambda
    options.seed = ...
        12345 + ll;


    % No need to store T x N x 1000 residuals for this exercise

    options.store_residuals = ...
        false;


    options.verbose = ...
        false;


    %% ESTIMATE

    tic;


    B = ...
        bvar_soe( ...
            y, ...
            p, ...
            n_foreign, ...
            options);


    elapsed = ...
        toc;


    fprintf('Elapsed time: %.2f seconds\n',elapsed);


    BVAR_lambda{ll} = ...
        B;


    roots = ...
        B.root_draws;


    %% ROOT STATISTICS

    MeanPhiRoot(ll) = ...
        B.root_mean_phi;


    MedianPhiRoot(ll) = ...
        B.root_median_phi;


    MedianDrawRoot(ll) = ...
        median(roots);


    P70Root(ll) = ...
        quantile(roots,0.70);


    P90Root(ll) = ...
        quantile(roots,0.90);


    P95Root(ll) = ...
        quantile(roots,0.95);


    P99Root(ll) = ...
        quantile(roots,0.99);


    MaxRoot(ll) = ...
        max(roots);


    PercentUnstable(ll) = ...
        100*mean(roots >= 1);


    fprintf('Posterior mean root: %.4f\n', ...
        MeanPhiRoot(ll));

    fprintf('Median draw root:    %.4f\n', ...
        MedianDrawRoot(ll));

    fprintf('Unstable draws:      %.1f%%\n', ...
        PercentUnstable(ll));

end


%% SUMMARY TABLE

LambdaSummary = table( ...
    lambdaGrid(:), ...
    MeanPhiRoot, ...
    MedianPhiRoot, ...
    MedianDrawRoot, ...
    P70Root, ...
    P90Root, ...
    P95Root, ...
    P99Root, ...
    MaxRoot, ...
    PercentUnstable, ...
    'VariableNames', ...
    { ...
    'Lambda', ...
    'PosteriorMeanPhiRoot', ...
    'PosteriorMedianPhiRoot', ...
    'MedianDrawRoot', ...
    'P70DrawRoot', ...
    'P90DrawRoot', ...
    'P95DrawRoot', ...
    'P99DrawRoot', ...
    'MaximumDrawRoot', ...
    'PercentUnstableDraws'});


fprintf('\n');
fprintf('============================================================\n');
fprintf('MINNESOTA TIGHTNESS SENSITIVITY\n');
fprintf('============================================================\n');

disp(LambdaSummary);


%% ROOT DISTRIBUTIONS
%
% Use empirical CDF rather than ksdensity so this does not depend
% on kernel-density functionality.

figure( ...
    'Color','w', ...
    'Position',[120 120 900 500]);


hold on;


for ll = 1:nLambda

    roots = ...
        sort(BVAR_lambda{ll}.root_draws);


    empiricalCDF = ...
        (1:length(roots))' / length(roots);


    plot( ...
        roots, ...
        empiricalCDF, ...
        'LineWidth',1.8);

end


xline( ...
    1, ...
    'k-', ...
    'Unit root', ...
    'LineWidth',1.3, ...
    'HandleVisibility','off');


xline( ...
    root_ols, ...
    'k--', ...
    'Classical SVAR', ...
    'LineWidth',1.2, ...
    'HandleVisibility','off');


grid on;
box off;


xlabel('Maximum companion root');

ylabel('Posterior cumulative probability');


title( ...
    'BVAR Persistence Across Minnesota Prior Tightness');


legend( ...
    '\lambda = 0.10', ...
    '\lambda = 0.20', ...
    '\lambda = 0.30', ...
    'Location','best');


%% UNSTABLE SHARE FIGURE

figure( ...
    'Color','w', ...
    'Position',[200 150 650 420]);


bar( ...
    lambdaGrid, ...
    PercentUnstable);


grid on;
box off;


xlabel('Minnesota tightness parameter, \lambda');

ylabel('Posterior draws with root \geq 1 (%)');


title( ...
    'Unstable Posterior Mass Across Prior Tightness');


xticks(lambdaGrid);


%% SAVE

save( ...
    fullfile( ...
        resultDir, ...
        'bvar_lambda_sensitivity.mat'), ...
    'LambdaSummary', ...
    'BVAR_lambda', ...
    'lambdaGrid', ...
    '-v7.3');