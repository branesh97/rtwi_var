%% ================================================================
%  AUSTRALIAN DOLLAR DRIVERS - SVAR LAG ROBUSTNESS
%
%  Compare p = 1, 2, 3
%
%  Everything else held fixed:
%
%  1. US real GDP gap
%  2. Commodity prices
%  3. VIX
%  4. Australian real GDP gap
%  5. Trimmed mean inflation
%  6. AU-US 2-year yield spread
%  7. Real TWI
%
%  Sample: 1995Q1-2026Q2
%  SOE foreign block: first 3 variables
%  Recursive ordering unchanged
%
%  Outputs:
%   - AIC / BIC / HQIC
%   - maximum companion root
%   - RTWI IRFs across lag lengths
%   - RTWI FEVD across lag lengths
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

            data.(v) = datetime(data.(v));

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


fprintf('\n============================================================\n');
fprintf('SVAR LAG-LENGTH ROBUSTNESS\n');
fprintf('============================================================\n');

fprintf('Sample: 1995Q1-2026Q2\n');
fprintf('T = %d\n',T);


%% 6. TRANSFORM VARIABLES
%
% Identical to baseline SVAR.


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
%
% IMPORTANT:
% Trends remain identical across p = 1, 2, 3.


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


%% 8. DATASET

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


N = ...
    size(y,2);


assert(N == 7);


%% 9. SETTINGS

pList = ...
    [1 2 3];


M = ...
    length(pList);


n_foreign = 3;


shock_comm = 2;
shock_vix = 3;
shock_spread = 6;
shock_er = 7;


hor = 24;

plot_hor = 16;

hor_fevd = 40;


fevdHorizons = ...
    [1 4 8 12 20];


% Presentation shocks

size_comm_shock = 10;

size_vix_shock = 10;

size_spread_shock = 1;


% No deterministic controls

d = ...
    zeros(T,0);


%% 10. STORAGE

maxRoot = ...
    nan(M,1);


logLikelihood = ...
    nan(M,1);

AIC = ...
    nan(M,1);

BIC = ...
    nan(M,1);

HQIC = ...
    nan(M,1);

nParameters = ...
    nan(M,1);


rtwi_comm = ...
    nan(M,hor+1);

rtwi_vix = ...
    nan(M,hor+1);

rtwi_spread = ...
    nan(M,hor+1);


FEVD_comm = ...
    nan(M,length(fevdHorizons));

FEVD_vix = ...
    nan(M,length(fevdHorizons));

FEVD_spread = ...
    nan(M,length(fevdHorizons));

FEVD_fx = ...
    nan(M,length(fevdHorizons));


results_lag = ...
    struct([]);


%% 11. ESTIMATE p = 1, 2, 3

for mm = 1:M

    p = ...
        pList(mm);


    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('ESTIMATING VAR(%d)\n',p);
    fprintf('============================================================\n');


    %% REDUCED-FORM SOE VAR

    [phi,gamma,SIGMA,X,e] = ...
        olsvar_soe( ...
            y, ...
            p, ...
            d, ...
            n_foreign);


    %% ------------------------------------------------------------
    % STABILITY
    %% ------------------------------------------------------------

    Companion = [ ...
        phi(2:end,:)'; ...
        eye(N*(p-1)) zeros(N*(p-1),N)];


    rootsVAR = ...
        eig(Companion);


    maxRoot(mm) = ...
        max(abs(rootsVAR));


    fprintf('Maximum root: %.4f\n', ...
        maxRoot(mm));


    %% ------------------------------------------------------------
    % INFORMATION CRITERIA
    %
    % Use Gaussian system likelihood based on MLE residual covariance.
    %
    % Parameter count respects SOE restrictions:
    %
    % Foreign equations:
    %   constant + p*n_foreign lags
    %
    % Domestic equations:
    %   constant + p*N lags
    %
    % Covariance parameters:
    %   N*(N+1)/2
    %
    % Because olsvar_soe uses the lecture-code mean-backcasting
    % convention, treat these ICs as comparative diagnostics rather
    % than an exact textbook lag-selection likelihood.
    %% ------------------------------------------------------------

    SigmaMLE = ...
        (e'*e)/T;


    R = ...
        chol(SigmaMLE);


    logDetSigma = ...
        2*sum(log(diag(R)));


    logLikelihood(mm) = ...
        -(T/2) * ...
        ( ...
        N*(1 + log(2*pi)) ...
        + logDetSigma ...
        );


    q = ...
        size(d,2);


    kForeignEq = ...
        1 + p*n_foreign + q;


    kDomesticEq = ...
        1 + p*N + q;


    kRegression = ...
        n_foreign*kForeignEq ...
        + (N-n_foreign)*kDomesticEq;


    kCovariance = ...
        N*(N+1)/2;


    kTotal = ...
        kRegression + kCovariance;


    nParameters(mm) = ...
        kTotal;


    AIC(mm) = ...
        -2*logLikelihood(mm) ...
        + 2*kTotal;


    BIC(mm) = ...
        -2*logLikelihood(mm) ...
        + log(T)*kTotal;


    HQIC(mm) = ...
        -2*logLikelihood(mm) ...
        + 2*log(log(T))*kTotal;


    %% ------------------------------------------------------------
    % IDENTIFICATION
    %% ------------------------------------------------------------

    [B,cholFlag] = ...
        chol(SIGMA,'lower');


    assert(cholFlag == 0, ...
        'SIGMA is not positive definite for VAR(%d).',p);


    %% ------------------------------------------------------------
    % COMMODITY SHOCK
    %% ------------------------------------------------------------

    resp = ...
        normalizedShockResponse( ...
            phi, ...
            B, ...
            shock_comm, ...
            size_comm_shock, ...
            hor);


    rtwi_comm(mm,:) = ...
        resp(shock_er,:);


    %% ------------------------------------------------------------
    % VIX SHOCK
    %% ------------------------------------------------------------

    resp = ...
        normalizedShockResponse( ...
            phi, ...
            B, ...
            shock_vix, ...
            size_vix_shock, ...
            hor);


    rtwi_vix(mm,:) = ...
        resp(shock_er,:);


    %% ------------------------------------------------------------
    % RELATIVE-YIELD SHOCK
    %% ------------------------------------------------------------

    resp = ...
        normalizedShockResponse( ...
            phi, ...
            B, ...
            shock_spread, ...
            size_spread_shock, ...
            hor);


    rtwi_spread(mm,:) = ...
        resp(shock_er,:);


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
                shock_er, ...
                :, ...
                fevdHorizons));


    FEVD_comm(mm,:) = ...
        rtwiFEVD(shock_comm,:);


    FEVD_vix(mm,:) = ...
        rtwiFEVD(shock_vix,:);


    FEVD_spread(mm,:) = ...
        rtwiFEVD(shock_spread,:);


    FEVD_fx(mm,:) = ...
        rtwiFEVD(shock_er,:);


    %% ------------------------------------------------------------
    % STORE RESULTS
    %% ------------------------------------------------------------

    results_lag(mm).p = ...
        p;

    results_lag(mm).phi = ...
        phi;

    results_lag(mm).SIGMA = ...
        SIGMA;

    results_lag(mm).B = ...
        B;

    results_lag(mm).roots = ...
        rootsVAR;

    results_lag(mm).maxRoot = ...
        maxRoot(mm);

    results_lag(mm).AIC = ...
        AIC(mm);

    results_lag(mm).BIC = ...
        BIC(mm);

    results_lag(mm).HQIC = ...
        HQIC(mm);

    results_lag(mm).rtwi_comm = ...
        rtwi_comm(mm,:);

    results_lag(mm).rtwi_vix = ...
        rtwi_vix(mm,:);

    results_lag(mm).rtwi_spread = ...
        rtwi_spread(mm,:);

    results_lag(mm).rtwi_FEVD = ...
        rtwiFEVD;

end


%% 12. INFORMATION-CRITERIA / ROOT TABLE

LagSummary = table( ...
    pList(:), ...
    nParameters, ...
    maxRoot, ...
    logLikelihood, ...
    AIC, ...
    BIC, ...
    HQIC, ...
    'VariableNames', ...
    { ...
    'Lags', ...
    'Parameters', ...
    'MaximumRoot', ...
    'LogLikelihood', ...
    'AIC', ...
    'BIC', ...
    'HQIC'});


fprintf('\n');
fprintf('============================================================\n');
fprintf('LAG-LENGTH SUMMARY\n');
fprintf('============================================================\n');

disp(LagSummary);


[~,iAIC] = ...
    min(AIC);

[~,iBIC] = ...
    min(BIC);

[~,iHQ] = ...
    min(HQIC);


fprintf('Lowest AIC:  p = %d\n', ...
    pList(iAIC));

fprintf('Lowest BIC:  p = %d\n', ...
    pList(iBIC));

fprintf('Lowest HQIC: p = %d\n', ...
    pList(iHQ));


%% 13. RTWI IRF OVERLAYS

h = ...
    0:hor;


modelLabels = ...
    compose('p = %d',pList);


figure( ...
    'Color','w', ...
    'Position',[80 100 1200 390]);


tiledlayout( ...
    1,3, ...
    'TileSpacing','compact', ...
    'Padding','compact');


%% Commodity

nexttile;

hold on;


for mm = 1:M

    plot( ...
        h(1:plot_hor+1), ...
        rtwi_comm(mm,1:plot_hor+1), ...
        'LineWidth',1.8);

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

xlim([0 plot_hor]);


legend( ...
    modelLabels, ...
    'Location','best');


%% VIX

nexttile;

hold on;


for mm = 1:M

    plot( ...
        h(1:plot_hor+1), ...
        rtwi_vix(mm,1:plot_hor+1), ...
        'LineWidth',1.8);

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

xlim([0 plot_hor]);


%% Spread

nexttile;

hold on;


for mm = 1:M

    plot( ...
        h(1:plot_hor+1), ...
        rtwi_spread(mm,1:plot_hor+1), ...
        'LineWidth',1.8);

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

xlim([0 plot_hor]);


sgtitle( ...
    'RTWI Impulse Responses Across VAR Lag Lengths');


exportgraphics( ...
    gcf, ...
    fullfile( ...
        figDir, ...
        '19_svar_lag_robustness_irfs.png'), ...
    'Resolution',300);


%% 14. FEVD OVERLAYS

figure( ...
    'Color','w', ...
    'Position',[80 100 1200 390]);


tiledlayout( ...
    1,3, ...
    'TileSpacing','compact', ...
    'Padding','compact');


%% Commodity FEVD

nexttile;

hold on;


for mm = 1:M

    plot( ...
        fevdHorizons, ...
        FEVD_comm(mm,:), ...
        '-o', ...
        'LineWidth',1.6);

end


grid on;
box off;


title('Commodity-price shock');

xlabel('Forecast horizon');
ylabel('Share of RTWI FE variance (%)');

xticks(fevdHorizons);


legend( ...
    modelLabels, ...
    'Location','best');


%% VIX FEVD

nexttile;

hold on;


for mm = 1:M

    plot( ...
        fevdHorizons, ...
        FEVD_vix(mm,:), ...
        '-o', ...
        'LineWidth',1.6);

end


grid on;
box off;


title('VIX shock');

xlabel('Forecast horizon');
ylabel('Share of RTWI FE variance (%)');

xticks(fevdHorizons);


%% Spread FEVD

nexttile;

hold on;


for mm = 1:M

    plot( ...
        fevdHorizons, ...
        FEVD_spread(mm,:), ...
        '-o', ...
        'LineWidth',1.6);

end


grid on;
box off;


title('AU-US 2yr spread shock');

xlabel('Forecast horizon');
ylabel('Share of RTWI FE variance (%)');

xticks(fevdHorizons);


sgtitle( ...
    'RTWI FEVD Across VAR Lag Lengths');


exportgraphics( ...
    gcf, ...
    fullfile( ...
        figDir, ...
        '20_svar_lag_robustness_fevd.png'), ...
    'Resolution',300);


%% 15. ROOT COMPARISON

figure( ...
    'Color','w', ...
    'Position',[200 150 600 400]);


bar( ...
    pList, ...
    maxRoot);


hold on;


yline( ...
    1, ...
    'k:', ...
    'Unit root', ...
    'HandleVisibility','off');


grid on;
box off;


xlabel('VAR lag order');

ylabel('Maximum companion root');

title('Persistence Across Lag Specifications');

xticks(pList);


exportgraphics( ...
    gcf, ...
    fullfile( ...
        figDir, ...
        '21_svar_lag_robustness_roots.png'), ...
    'Resolution',300);


%% 16. LONG-FORM FEVD TABLE

FEVD_Table = table();


for mm = 1:M

    for hh = 1:length(fevdHorizons)

        newRow = table( ...
            pList(mm), ...
            fevdHorizons(hh), ...
            FEVD_comm(mm,hh), ...
            FEVD_vix(mm,hh), ...
            FEVD_spread(mm,hh), ...
            FEVD_fx(mm,hh), ...
            'VariableNames', ...
            { ...
            'Lags', ...
            'Horizon', ...
            'Commodity', ...
            'VIX', ...
            'Spread', ...
            'ResidualFX'});


        FEVD_Table = ...
            [FEVD_Table;newRow];

    end

end


fprintf('\n');
fprintf('============================================================\n');
fprintf('FEVD BY LAG LENGTH\n');
fprintf('============================================================\n');

disp(FEVD_Table);


%% 17. COMPACT IRF SUMMARY
%
% Impact and largest absolute response over first 16 quarters.


IRF_Summary = table();


for mm = 1:M

    p = ...
        pList(mm);


    %% Commodity

    x = ...
        rtwi_comm(mm,1:plot_hor+1);

    [~,idx] = ...
        max(abs(x));


    commImpact = ...
        x(1);

    commPeak = ...
        x(idx);

    commPeakH = ...
        idx-1;


    %% VIX

    x = ...
        rtwi_vix(mm,1:plot_hor+1);

    [~,idx] = ...
        max(abs(x));


    vixImpact = ...
        x(1);

    vixPeak = ...
        x(idx);

    vixPeakH = ...
        idx-1;


    %% Spread

    x = ...
        rtwi_spread(mm,1:plot_hor+1);

    [~,idx] = ...
        max(abs(x));


    spreadImpact = ...
        x(1);

    spreadPeak = ...
        x(idx);

    spreadPeakH = ...
        idx-1;


    newRow = table( ...
        p, ...
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
        'Lags', ...
        'CommodityImpact', ...
        'CommodityPeak', ...
        'CommodityPeakHorizon', ...
        'VIXImpact', ...
        'VIXPeak', ...
        'VIXPeakHorizon', ...
        'SpreadImpact', ...
        'SpreadPeak', ...
        'SpreadPeakHorizon'});


    IRF_Summary = ...
        [IRF_Summary;newRow];

end


disp(' ');
disp(IRF_Summary);


%% 18. EXPORT

outputFile = ...
    fullfile( ...
        resultDir, ...
        'svar_lag_robustness.xlsx');


if isfile(outputFile)
    delete(outputFile);
end


writetable( ...
    LagSummary, ...
    outputFile, ...
    'Sheet','lag_summary');


writetable( ...
    IRF_Summary, ...
    outputFile, ...
    'Sheet','IRF_summary');


writetable( ...
    FEVD_Table, ...
    outputFile, ...
    'Sheet','FEVD');


%% 19. SAVE MATLAB RESULTS

lag_results = struct();


lag_results.pList = ...
    pList;

lag_results.LagSummary = ...
    LagSummary;

lag_results.IRF_Summary = ...
    IRF_Summary;

lag_results.FEVD_Table = ...
    FEVD_Table;


lag_results.rtwi_comm = ...
    rtwi_comm;

lag_results.rtwi_vix = ...
    rtwi_vix;

lag_results.rtwi_spread = ...
    rtwi_spread;


lag_results.FEVD_comm = ...
    FEVD_comm;

lag_results.FEVD_vix = ...
    FEVD_vix;

lag_results.FEVD_spread = ...
    FEVD_spread;

lag_results.FEVD_fx = ...
    FEVD_fx;


lag_results.models = ...
    results_lag;


save( ...
    fullfile( ...
        resultDir, ...
        'svar_lag_robustness.mat'), ...
    'lag_results');


%% 20. FINAL SUMMARY

fprintf('\n============================================================\n');
fprintf('LAG ROBUSTNESS COMPLETE\n');
fprintf('============================================================\n');


disp(LagSummary);


fprintf('\nResults workbook:\n%s\n', ...
    outputFile);


%% ================================================================
% LOCAL FUNCTION
%% ================================================================

function response = normalizedShockResponse( ...
    phi, ...
    B, ...
    shockIndex, ...
    shockSize, ...
    hor)


    N = ...
        size(B,1);


    Bn = ...
        B;


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


end