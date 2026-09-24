%% ================================================================
%  AUSTRALIAN DOLLAR DRIVERS - INITIAL DESCRIPTIVE ANALYSIS
%
%  Commodity prices, interest rates or fear?
%
%  Data: data_collected.xlsx, sheet "data"
%  Main exploratory sample: 1985Q1-2026Q2
%
%  Positive change in RTWI = AUD appreciation
%% ================================================================

clear;
clc;
close all;

% Folder containing this script
folder = fileparts(mfilename('fullpath'));

% Add datafolder
addpath(fullfile(folder,'data'))

%% 1. SETTINGS

fileName  = fullfile(folder,'data','data_collected.xlsx');
sheetName = 'data';

sampleStart = datetime(1985,1,1);

% Number of quarters used for lead-lag correlations
maxLeadLag = 4;

% Folder for figures
figDir    = fullfile(folder,'figures');
if ~exist(figDir,'dir')
    mkdir(figDir);
end

% Folder for results
resultDir = fullfile(folder,'results');
if ~exist(resultDir,'dir')
    mkdir(resultDir);
end


%% 2. IMPORT DATA

data = readtable(fileName, ...
    'Sheet',sheetName, ...
    'VariableNamingRule','preserve');

% Convert common text missing-value indicators into missing values
data = standardizeMissing(data,{'NA','N/A','na',''});


%% 3. MAKE SURE DATE VARIABLES ARE DATETIME

dateVars = {'quarter_start','quarter_end'};

for i = 1:length(dateVars)

    v = dateVars{i};

    if ~isdatetime(data.(v))

        if isnumeric(data.(v))

            % Excel serial date
            data.(v) = datetime(data.(v), ...
                'ConvertFrom','excel');

        else

            data.(v) = datetime(data.(v));

        end

    end

end


%% 4. MAKE SURE ALL OTHER VARIABLES ARE NUMERIC
%
% This makes the import robust in case MATLAB reads a column containing
% "NA" as text rather than numeric.

varNames = data.Properties.VariableNames;

for j = 3:width(data)

    v = varNames{j};

    if ~isnumeric(data.(v))

        data.(v) = str2double(string(data.(v)));

    end

end


%% 5. YEARLAB AND QUARTER LABELS
%
% Same convention as the replication:
%
% 1985Q1 = 1985.00
% 1985Q2 = 1985.25
% 1985Q3 = 1985.50
% 1985Q4 = 1985.75

yr = year(data.quarter_start);
qtr = ceil(month(data.quarter_start)/3);

yearlab = yr + (qtr-1)/4;

quarterlab = string(yr) + "Q" + string(qtr);

fprintf('Full dataset: %s to %s\n', ...
    char(quarterlab(1)),char(quarterlab(end)));

fprintf('Number of quarterly observations: %d\n\n',height(data));


%% 6. CREATE TRANSFORMED VARIABLES
%
% Exchange rates and price variables:
%     100 * change in log
%
% Interest-rate spreads:
%     first difference in percentage points
%
% Uncertainty:
%     100 * change in log index
%
% These are intended for the simple correlation analysis.
% VAR transformations can be reconsidered separately later.


% -------------------------
% Exchange rates
% -------------------------

data.d_rtwi    = logdiff100(data.rtwi);
data.d_ntwi    = logdiff100(data.ntwi);
data.d_aud_usd = logdiff100(data.aud_usd);


% -------------------------
% Foreign and domestic GDP
% -------------------------

data.d_us_rgdp = logdiff100(data.us_rgdp);
data.d_au_rgdp = logdiff100(data.au_rgdp);


% -------------------------
% Commodity / external prices
% -------------------------

data.d_tot          = logdiff100(data.tot);
data.d_comm_price   = logdiff100(data.comm_price);
data.d_comm_bulk    = logdiff100(data.comm_price_bulk);

data.d_iron_ore     = logdiff100(data.iron_ore);
data.d_coal         = logdiff100(data.coal);
data.d_brent_crude  = logdiff100(data.brent_crude);
data.d_natural_gas  = logdiff100(data.natural_gas);


% -------------------------
% Interest-rate differentials
% -------------------------

data.d_policy_spread = firstdiff(data.au_us_policy_rate);
data.d_2yr_spread    = firstdiff(data.au_us_2yr);
data.d_10yr_spread   = firstdiff(data.au_us_10yr);


% -------------------------
% Uncertainty / fear
% -------------------------

data.ln_vix         = log(data.vix);
data.ln_gepu        = log(data.gepu);
data.ln_gpr_global  = log(data.gpr_global);
data.ln_gprt_global = log(data.gprt_global);
data.ln_gpra_global = log(data.gpra_global);
data.ln_au_epu      = log(data.au_epu);

data.dln_vix         = logdiff100(data.vix);
data.dln_gepu        = logdiff100(data.gepu);
data.dln_gpr_global  = logdiff100(data.gpr_global);
data.dln_gprt_global = logdiff100(data.gprt_global);
data.dln_gpra_global = logdiff100(data.gpra_global);
data.dln_au_epu      = logdiff100(data.au_epu);

% WUI contains zeros, so use ordinary first differences rather than logs
data.d_wui_au = firstdiff(data.wui_au);

% Australian country-specific GPR series
data.d_gprc_au = firstdiff(data.gprc_au);


%% 7. MAIN SAMPLE: 1985Q1 TO LATEST COMPLETE QUARTER

sampleEnd = max(data.quarter_start);

mainSample = ...
    data.quarter_start >= sampleStart & ...
    data.quarter_start <= sampleEnd;

D = data(mainSample,:);
yearlab_main = yearlab(mainSample);
quarterlab_main = quarterlab(mainSample);

fprintf('Main sample: %s to %s\n', ...
    char(quarterlab_main(1)),char(quarterlab_main(end)));

fprintf('Observations: %d\n\n',height(D));


%% 8. BASIC RTWI PLOT

figure('Color','w','Position',[100 100 1000 420]);

plot(yearlab_main,D.rtwi,'LineWidth',1.5);

grid on;
box off;

xlabel('Year');
ylabel('Real TWI');
title('Australian Dollar Real Trade-Weighted Index');

xlim([yearlab_main(1) yearlab_main(end)]);

tickStart = ceil(yearlab_main(1)/5)*5;
tickEnd   = floor(yearlab_main(end)/5)*5;

xticks(tickStart:5:tickEnd);

exportgraphics(gcf, ...
    fullfile(figDir,'01_rtwi_level.png'), ...
    'Resolution',300);


%% 9. OVERVIEW OF THREE MAIN CHANNELS
%
% Variables are standardised here only to make movements visually
% comparable. They retain their original economic interpretation.

figure('Color','w','Position',[100 50 1100 850]);

tiledlayout(3,1, ...
    'TileSpacing','compact', ...
    'Padding','compact');


% ================================================================
% A. COMMODITY CHANNEL
% ================================================================

nexttile;

plot(yearlab_main,zomit(log(D.rtwi)), ...
    'LineWidth',1.4);
hold on;

plot(yearlab_main,zomit(log(D.comm_price)), ...
    'LineWidth',1.2);

plot(yearlab_main,zomit(log(D.tot)), ...
    'LineWidth',1.2);

yline(0,'k:');

grid on;
box off;

ylabel('Standard deviations');

title('Commodity-price channel');

legend( ...
    'Real TWI', ...
    'RBA Commodity Price Index (SDR)', ...
    'Terms of Trade', ...
    'Location','best');

xlim([yearlab_main(1) yearlab_main(end)]);
xticks(tickStart:5:tickEnd);


% ================================================================
% B. INTEREST-RATE CHANNEL
% ================================================================

nexttile;

plot(yearlab_main,zomit(log(D.rtwi)), ...
    'LineWidth',1.4);
hold on;

plot(yearlab_main,zomit(D.au_us_policy_rate), ...
    'LineWidth',1.2);

plot(yearlab_main,zomit(D.au_us_2yr), ...
    'LineWidth',1.2);

plot(yearlab_main,zomit(D.au_us_10yr), ...
    'LineWidth',1.2);

yline(0,'k:');

grid on;
box off;

ylabel('Standard deviations');

title('Relative interest-rate channel');

legend( ...
    'Real TWI', ...
    'AU-US policy rate spread', ...
    'AU-US 2-year yield spread', ...
    'AU-US 10-year yield spread', ...
    'Location','best');

xlim([yearlab_main(1) yearlab_main(end)]);
xticks(tickStart:5:tickEnd);


% ================================================================
% C. GLOBAL UNCERTAINTY / FEAR CHANNEL
% ================================================================

nexttile;

plot(yearlab_main,zomit(log(D.rtwi)), ...
    'LineWidth',1.4);
hold on;

plot(yearlab_main,zomit(D.ln_gpr_global), ...
    'LineWidth',1.2);

plot(yearlab_main,zomit(D.ln_vix), ...
    'LineWidth',1.2);

plot(yearlab_main,zomit(D.ln_gepu), ...
    'LineWidth',1.2);

yline(0,'k:');

grid on;
box off;

xlabel('Year');
ylabel('Standard deviations');

title('Global uncertainty and risk channel');

legend( ...
    'Real TWI', ...
    'Global GPR', ...
    'VIX', ...
    'Global EPU', ...
    'Location','best');

xlim([yearlab_main(1) yearlab_main(end)]);
xticks(tickStart:5:tickEnd);


exportgraphics(gcf, ...
    fullfile(figDir,'02_three_channels_standardised.png'), ...
    'Resolution',300);


%% 10. INDIVIDUAL COMMODITY PRICE PLOTS
%
% Useful for seeing whether the aggregate RBA commodity index is being
% driven by a particular commodity episode.

commodityVars = { ...
    'd_iron_ore', ...
    'd_coal', ...
    'd_brent_crude', ...
    'd_natural_gas'};

commodityLabels = { ...
    'Iron ore', ...
    'Australian coal', ...
    'Brent crude oil', ...
    'Japan LNG'};

figure('Color','w','Position',[100 100 1100 700]);

tiledlayout(2,2, ...
    'TileSpacing','compact', ...
    'Padding','compact');

for i = 1:length(commodityVars)

    nexttile;

    x = D.(commodityVars{i});
    y = D.d_rtwi;

    valid = isfinite(x) & isfinite(y);

    scatter(x(valid),y(valid),15,'filled');
    hold on;

    % Simple fitted line for visual purposes only
    if sum(valid) >= 3

        b = polyfit(x(valid),y(valid),1);

        xx = linspace(min(x(valid)),max(x(valid)),100);
        yy = polyval(b,xx);

        plot(xx,yy,'LineWidth',1.4);

    end

    [r,~] = pairCorr(x,y);

    grid on;
    box off;

    xlabel(sprintf('%s quarterly log change (%%)', ...
        commodityLabels{i}));

    ylabel('RTWI quarterly log change (%)');

    title(sprintf('%s: r = %.2f', ...
        commodityLabels{i},r));

end

exportgraphics(gcf, ...
    fullfile(figDir,'03_individual_commodities_scatter.png'), ...
    'Resolution',300);


%% 11. MAIN SCATTERPLOTS
%
% These are deliberately "movement vs movement":
%
%   commodity price change
%   interest-rate spread change
%   uncertainty change
%
% against the quarterly RTWI change.

scatterVars = { ...
    'd_comm_price', ...
    'd_tot', ...
    'd_policy_spread', ...
    'd_2yr_spread', ...
    'dln_vix', ...
    'dln_gepu', ...
    'dln_gpr_global', ...
    'dln_gprt_global'};

scatterLabels = { ...
    'Commodity prices', ...
    'Terms of trade', ...
    'AU-US policy-rate spread', ...
    'AU-US 2-year yield spread', ...
    'VIX', ...
    'Global EPU', ...
    'Global GPR', ...
    'Global GPR threats'};

figure('Color','w','Position',[50 50 1200 750]);

tiledlayout(2,4, ...
    'TileSpacing','compact', ...
    'Padding','compact');

for i = 1:length(scatterVars)

    nexttile;

    x = D.(scatterVars{i});
    y = D.d_rtwi;

    valid = isfinite(x) & isfinite(y);

    scatter(x(valid),y(valid),13,'filled');
    hold on;

    % Fitted line
    if sum(valid) >= 3

        b = polyfit(x(valid),y(valid),1);

        xx = linspace(min(x(valid)),max(x(valid)),100);
        yy = polyval(b,xx);

        plot(xx,yy,'LineWidth',1.3);

    end

    [r,n] = pairCorr(x,y);

    grid on;
    box off;

    xlabel(scatterLabels{i});
    ylabel('\Delta log RTWI (%)');

    title(sprintf('r = %.2f, N = %d',r,n));

end

sgtitle('Contemporaneous Relationships with Quarterly Australian Dollar Movements');


exportgraphics(gcf, ...
    fullfile(figDir,'04_main_scatterplots.png'), ...
    'Resolution',300);


%% 12. LEAD / CONTEMPORANEOUS / LAG CORRELATIONS
%
% IMPORTANT TIMING CONVENTION:
%
% h > 0:
%     factor X LEADS the AUD
%
% Example:
%     X_leads_2 = Corr(dRTWI_t , X_{t-2})
%
% h = 0:
%     contemporaneous correlation
%
% h < 0:
%     factor X LAGS the AUD
%
% Example:
%     X_lags_2 = Corr(dRTWI_t , X_{t+2})


factorVars = { ...
    'd_us_rgdp', ...
    'd_tot', ...
    'd_comm_price', ...
    'd_iron_ore', ...
    'd_coal', ...
    'd_brent_crude', ...
    'd_natural_gas', ...
    'd_policy_spread', ...
    'd_2yr_spread', ...
    'd_10yr_spread', ...
    'dln_vix', ...
    'dln_gepu', ...
    'dln_gpr_global', ...
    'dln_gprt_global', ...
    'dln_gpra_global', ...
    'dln_au_epu', ...
    'd_wui_au', ...
    'd_gprc_au'};

factorLabels = { ...
    'US real GDP', ...
    'Terms of trade', ...
    'RBA commodity prices', ...
    'Iron ore', ...
    'Australian coal', ...
    'Brent crude oil', ...
    'Japan LNG', ...
    'AU-US policy-rate spread', ...
    'AU-US 2-year yield spread', ...
    'AU-US 10-year yield spread', ...
    'VIX', ...
    'Global EPU', ...
    'Global GPR', ...
    'Global GPR threats', ...
    'Global GPR acts', ...
    'Australian EPU', ...
    'Australian WUI', ...
    'Australian GPR'};


% Display columns from:
%
% X leads AUD by 4 quarters
% ...
% contemporaneous
% ...
% X lags AUD by 4 quarters

hVec = maxLeadLag:-1:-maxLeadLag;


[corrTableFull,corrMatFull,nMatFull] = ...
    makeLeadLagTable( ...
        data, ...
        mainSample, ...
        'd_rtwi', ...
        factorVars, ...
        factorLabels, ...
        hVec);


disp(' ');
disp('============================================================');
disp('LEAD-LAG CORRELATIONS: FULL AVAILABLE SAMPLE');
disp('============================================================');
disp(corrTableFull);


%% 13. COMMON-SAMPLE COMPARISON
%
% Global EPU starts in 1997.
%
% Using a common 1997Q1 sample lets us compare commodity prices,
% interest rates, VIX, EPU and GPR over exactly the same period.

commonStart = datetime(1997,1,1);

commonSample = ...
    data.quarter_start >= commonStart & ...
    data.quarter_start <= sampleEnd;


primaryVars = { ...
    'd_comm_price', ...
    'd_policy_spread', ...
    'd_2yr_spread', ...
    'dln_vix', ...
    'dln_gepu', ...
    'dln_gpr_global'};

primaryLabels = { ...
    'RBA commodity prices', ...
    'AU-US policy-rate spread', ...
    'AU-US 2-year yield spread', ...
    'VIX', ...
    'Global EPU', ...
    'Global GPR'};


[corrTableCommon,corrMatCommon,nMatCommon] = ...
    makeLeadLagTable( ...
        data, ...
        commonSample, ...
        'd_rtwi', ...
        primaryVars, ...
        primaryLabels, ...
        hVec);


disp(' ');
disp('============================================================');
disp('LEAD-LAG CORRELATIONS: COMMON 1997Q1-2026Q2 SAMPLE');
disp('============================================================');
disp(corrTableCommon);


%% 14. PRE-COVID COMMON-SAMPLE CHECK
%
% This helps us see whether COVID-era observations dominate the
% descriptive correlations.

preCovidSample = ...
    data.quarter_start >= commonStart & ...
    data.quarter_start <= datetime(2019,10,1);


[corrTablePreCovid,corrMatPreCovid,nMatPreCovid] = ...
    makeLeadLagTable( ...
        data, ...
        preCovidSample, ...
        'd_rtwi', ...
        primaryVars, ...
        primaryLabels, ...
        hVec);


disp(' ');
disp('============================================================');
disp('LEAD-LAG CORRELATIONS: COMMON 1997Q1-2019Q4 SAMPLE');
disp('============================================================');
disp(corrTablePreCovid);


%% 15. EXPORT CORRELATION TABLES TO EXCEL

corrFile = fullfile(resultDir,'initial_correlation_tables.xlsx');

if isfile(corrFile)
    delete(corrFile);
end

writetable( ...
    corrTableFull, ...
    corrFile, ...
    'Sheet','pairwise_full');

writetable( ...
    corrTableCommon, ...
    corrFile, ...
    'Sheet','common_1997');

writetable( ...
    corrTablePreCovid, ...
    corrFile, ...
    'Sheet','common_preCOVID');


fprintf('\nCorrelation tables saved to: %s\n',corrFile);


%% 16. LEAD-LAG CORRELATION HEATMAP
%
% I think this will be very useful for exploratory analysis.
%
% It shows immediately whether a factor tends to move before,
% at the same time as, or after the AUD.

heatLabels = { ...
    'Leads 4', ...
    'Leads 3', ...
    'Leads 2', ...
    'Leads 1', ...
    'Contemp.', ...
    'Lags 1', ...
    'Lags 2', ...
    'Lags 3', ...
    'Lags 4'};


figure('Color','w','Position',[100 50 1050 600]);

H = heatmap( ...
    heatLabels, ...
    primaryLabels, ...
    corrMatCommon);

H.ColorLimits = [-1 1];
H.CellLabelFormat = '%.2f';

H.Title = ...
    'Correlation of Factor Movements with Quarterly RTWI Changes';

H.XLabel = ...
    'Timing of factor relative to Australian dollar';

H.YLabel = ...
    'Factor';


exportgraphics(gcf, ...
    fullfile(figDir,'05_lead_lag_heatmap.png'), ...
    'Resolution',300);


%% 17. OPTIONAL: CONTEMPORANEOUS CORRELATIONS RANKED
%
% This gives a very quick descriptive answer to:
%
% "Which factor has the largest simple contemporaneous association
% with quarterly AUD movements?"
%
% This is NOT a causal ranking.

contempCol = find(hVec == 0);

r0 = corrMatCommon(:,contempCol);
n0 = nMatCommon(:,contempCol);

contempTable = table( ...
    string(primaryLabels(:)), ...
    r0, ...
    abs(r0), ...
    n0, ...
    'VariableNames', ...
    {'Factor','Correlation','AbsCorrelation','N'});

contempTable = sortrows( ...
    contempTable, ...
    'AbsCorrelation', ...
    'descend');

disp(' ');
disp('============================================================');
disp('CONTEMPORANEOUS CORRELATIONS - COMMON SAMPLE');
disp('============================================================');
disp(contempTable);

writetable( ...
    contempTable, ...
    corrFile, ...
    'Sheet','contemp_common');

%% 18. JOINT CONTEMPORANEOUS REGRESSIONS
%
% Question:
%
% When commodity prices, relative interest rates and global risk are
% considered jointly, which retain an independent contemporaneous
% association with the Australian dollar?
%
% Dependent variables:
%   d_rtwi      = real TWI quarterly log change
%   d_ntwi      = nominal TWI quarterly log change
%   d_aud_usd   = AUD/USD quarterly log change
%
% Note:
% AUD/USD is USD per AUD, so a positive change = AUD appreciation.
%
% Baseline common sample starts 1997Q1 because Global EPU begins there.
%
% Newey-West HAC standard errors with 4 quarterly lags are reported.


regStart = datetime(1997,1,1);
regEnd   = sampleEnd;

regSample = ...
    data.quarter_start >= regStart & ...
    data.quarter_start <= regEnd;

nwLags = 4;


%% MODEL DEFINITIONS
%
% Model 1:
% Commodity + 2-year yield spread + VIX
%
% Model 2:
% Model 1 + US GDP growth
%
% Model 3:
% Commodity + 2-year yield spread + Global EPU
%
% Model 4:
% Model 3 + US GDP growth
%
% Model 5:
% Commodity + 2-year yield spread + VIX + Global EPU + US GDP
%
% Model 6:
% Commodity + POLICY RATE spread + VIX + US GDP
%
% Model 6 lets us compare the current policy-rate differential with
% the more forward-looking 2-year yield differential.


modelNames = { ...
    'Commodity + 2yr + VIX', ...
    'Commodity + 2yr + VIX + US GDP', ...
    'Commodity + 2yr + GEPU', ...
    'Commodity + 2yr + GEPU + US GDP', ...
    'Commodity + 2yr + VIX + GEPU + US GDP', ...
    'Commodity + policy spread + VIX + US GDP'};


modelVars = { ...
    {'d_comm_price','d_2yr_spread','dln_vix'}, ...
    {'d_comm_price','d_2yr_spread','dln_vix','d_us_rgdp'}, ...
    {'d_comm_price','d_2yr_spread','dln_gepu'}, ...
    {'d_comm_price','d_2yr_spread','dln_gepu','d_us_rgdp'}, ...
    {'d_comm_price','d_2yr_spread','dln_vix','dln_gepu','d_us_rgdp'}, ...
    {'d_comm_price','d_policy_spread','dln_vix','d_us_rgdp'}};


modelLabels = { ...
    {'Commodity','2yr spread','VIX'}, ...
    {'Commodity','2yr spread','VIX','US GDP'}, ...
    {'Commodity','2yr spread','GEPU'}, ...
    {'Commodity','2yr spread','GEPU','US GDP'}, ...
    {'Commodity','2yr spread','VIX','GEPU','US GDP'}, ...
    {'Commodity','Policy spread','VIX','US GDP'}};


%% EXCHANGE-RATE OUTCOMES

yVars = { ...
    'd_rtwi', ...
    'd_ntwi', ...
    'd_aud_usd'};

yLabels = { ...
    'Real TWI', ...
    'Nominal TWI', ...
    'AUD/USD'};


%% RUN ALL REGRESSIONS

allRegResults = table();

for yy = 1:length(yVars)

    yVar = yVars{yy};

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('%s REGRESSIONS\n',upper(yLabels{yy}));
    fprintf('Sample: 1997Q1 to 2026Q2\n');
    fprintf('Newey-West lags: %d\n',nwLags);
    fprintf('============================================================\n');

    for mm = 1:length(modelNames)

        xVars   = modelVars{mm};
        xLabels = modelLabels{mm};

        [resTbl,stats] = runHACRegression( ...
            data, ...
            regSample, ...
            yVar, ...
            xVars, ...
            xLabels, ...
            nwLags);

        fprintf('\nMODEL %d: %s\n',mm,modelNames{mm});
        disp(resTbl);

        fprintf('N = %d, R2 = %.3f, Adj R2 = %.3f\n', ...
            stats.N,stats.R2,stats.AdjR2);

        % Add identifiers for combined export table
        nrows = height(resTbl);

        tmp = addvars( ...
            resTbl, ...
            repmat(string(yLabels{yy}),nrows,1), ...
            repmat(string(modelNames{mm}),nrows,1), ...
            repmat(stats.N,nrows,1), ...
            repmat(stats.R2,nrows,1), ...
            repmat(stats.AdjR2,nrows,1), ...
            'Before',1, ...
            'NewVariableNames', ...
            {'ExchangeRate','Model','N','R2','AdjR2'});

        allRegResults = [allRegResults; tmp];

    end

end


%% EXPORT FULL REGRESSION RESULTS

regFile = fullfile(resultDir,'joint_regression_results.xlsx');

if isfile(regFile)
    delete(regFile);
end

writetable( ...
    allRegResults, ...
    regFile, ...
    'Sheet','all_results');

fprintf('\nFull regression results saved to:\n%s\n',regFile);

%% 19. COMPACT TABLE OF MAIN COEFFICIENTS
%
% Focuses on:
%
% Commodity price change
% AU-US 2-year yield-spread change
% VIX change
% Global EPU change
%
% across all three AUD measures.


mainCoefNames = { ...
    'Commodity', ...
    '2yr spread', ...
    'VIX', ...
    'GEPU'};

compactResults = table();


for yy = 1:length(yVars)

    yVar = yVars{yy};

    for mm = 1:5
        % Model 6 uses policy spread, so exclude it from this particular
        % compact comparison.

        [resTbl,stats] = runHACRegression( ...
            data, ...
            regSample, ...
            yVar, ...
            modelVars{mm}, ...
            modelLabels{mm}, ...
            nwLags);

        for cc = 1:length(mainCoefNames)

            row = find( ...
                strcmp(resTbl.Variable,mainCoefNames{cc}), ...
                1);

            if isempty(row)

                beta = NaN;
                se   = NaN;
                tval = NaN;
                pval = NaN;

            else

                beta = resTbl.Coefficient(row);
                se   = resTbl.HAC_SE(row);
                tval = resTbl.tStatistic(row);
                pval = resTbl.pValue(row);

            end

            newRow = table( ...
                string(yLabels{yy}), ...
                string(modelNames{mm}), ...
                string(mainCoefNames{cc}), ...
                beta, ...
                se, ...
                tval, ...
                pval, ...
                stats.N, ...
                stats.R2, ...
                'VariableNames', ...
                {'ExchangeRate','Model','Variable', ...
                'Coefficient','HAC_SE','tStatistic','pValue','N','R2'});

            compactResults = [compactResults; newRow];

        end

    end

end


writetable( ...
    compactResults, ...
    regFile, ...
    'Sheet','compact_results');

%% 20. HEADLINE THREE-FACTOR REGRESSION
%
% Commodity prices
% + AU-US 2-year yield differential
% + VIX
%
% Run for:
%   Real TWI
%   Nominal TWI
%   AUD/USD
%
% Same common 1997Q1 sample.


headlineVars = { ...
    'd_comm_price', ...
    'd_2yr_spread', ...
    'dln_vix'};

headlineLabels = { ...
    'Commodity', ...
    '2yr spread', ...
    'VIX'};


headlineTable = table();


for yy = 1:length(yVars)

    [resTbl,stats] = runHACRegression( ...
        data, ...
        regSample, ...
        yVars{yy}, ...
        headlineVars, ...
        headlineLabels, ...
        nwLags);

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('HEADLINE REGRESSION: %s\n',yLabels{yy});
    fprintf('============================================================\n');

    disp(resTbl);

    fprintf('N = %d, R2 = %.3f, Adj R2 = %.3f\n', ...
        stats.N,stats.R2,stats.AdjR2);


    % Remove intercept for compact presentation
    keep = ~strcmp(resTbl.Variable,'Constant');

    temp = resTbl(keep,:);

    temp = addvars( ...
        temp, ...
        repmat(string(yLabels{yy}),height(temp),1), ...
        repmat(stats.N,height(temp),1), ...
        repmat(stats.R2,height(temp),1), ...
        'Before',1, ...
        'NewVariableNames', ...
        {'ExchangeRate','N','R2'});

    headlineTable = [headlineTable; temp];

end


writetable( ...
    headlineTable, ...
    regFile, ...
    'Sheet','headline_three_factor');

%% 21. HEADLINE REGRESSION WITH US GDP CONTROL

headlineControlVars = { ...
    'd_comm_price', ...
    'd_2yr_spread', ...
    'dln_vix', ...
    'd_us_rgdp'};

headlineControlLabels = { ...
    'Commodity', ...
    '2yr spread', ...
    'VIX', ...
    'US GDP'};


headlineControlTable = table();


for yy = 1:length(yVars)

    [resTbl,stats] = runHACRegression( ...
        data, ...
        regSample, ...
        yVars{yy}, ...
        headlineControlVars, ...
        headlineControlLabels, ...
        nwLags);

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('HEADLINE + US GDP: %s\n',yLabels{yy});
    fprintf('============================================================\n');

    disp(resTbl);

    fprintf('N = %d, R2 = %.3f, Adj R2 = %.3f\n', ...
        stats.N,stats.R2,stats.AdjR2);


    keep = ~strcmp(resTbl.Variable,'Constant');

    temp = resTbl(keep,:);

    temp = addvars( ...
        temp, ...
        repmat(string(yLabels{yy}),height(temp),1), ...
        repmat(stats.N,height(temp),1), ...
        repmat(stats.R2,height(temp),1), ...
        'Before',1, ...
        'NewVariableNames', ...
        {'ExchangeRate','N','R2'});

    headlineControlTable = [headlineControlTable; temp];

end


writetable( ...
    headlineControlTable, ...
    regFile, ...
    'Sheet','headline_plus_USGDP');

%% 22. STANDARDISED HEADLINE REGRESSION
%
% Standardise Y and X within the common regression sample.
%
% Coefficients can then be interpreted as:
%
% "A one-standard-deviation increase in X is associated with a
% beta-standard-deviation change in the exchange rate."


standardisedTable = table();

betaMatrix = nan(length(yVars),length(headlineVars));


for yy = 1:length(yVars)

    y = data.(yVars{yy});

    X = nan(height(data),length(headlineVars));

    for xx = 1:length(headlineVars)
        X(:,xx) = data.(headlineVars{xx});
    end


    % Common valid observations
    valid = regSample & ...
        isfinite(y) & ...
        all(isfinite(X),2);

    ys = y(valid);
    Xs = X(valid,:);


    % Standardise
    ys = (ys - mean(ys)) ./ std(ys);

    for xx = 1:size(Xs,2)
        Xs(:,xx) = ...
            (Xs(:,xx) - mean(Xs(:,xx))) ./ std(Xs(:,xx));
    end


    % Estimate HAC regression
    [beta,se,tval,pval,stats] = ...
        olsNeweyWest(ys,Xs,nwLags);

    % Exclude intercept
    betaMatrix(yy,:) = beta(2:end)';


    temp = table( ...
        repmat(string(yLabels{yy}),length(headlineVars),1), ...
        string(headlineLabels(:)), ...
        beta(2:end), ...
        se(2:end), ...
        tval(2:end), ...
        pval(2:end), ...
        'VariableNames', ...
        {'ExchangeRate','Variable', ...
        'StandardisedBeta','HAC_SE','tStatistic','pValue'});

    standardisedTable = [standardisedTable; temp];

end


writetable( ...
    standardisedTable, ...
    regFile, ...
    'Sheet','standardised_headline');


%% STANDARDISED COEFFICIENT PLOT

figure('Color','w','Position',[100 100 950 500]);

b = bar(betaMatrix');

grid on;
box off;

xticklabels(headlineLabels);

ylabel('Standardised coefficient');

title( ...
    'Commodity Prices, Relative Rates and Risk: Joint Associations with the AUD');

legend( ...
    yLabels, ...
    'Location','best');

yline(0,'k:','HandleVisibility','off');

exportgraphics( ...
    gcf, ...
    fullfile(figDir,'06_standardised_joint_coefficients.png'), ...
    'Resolution',300);

%% 23. CORRELATIONS AMONG MAIN REGRESSORS + VIFs
%
% Purpose:
% Check whether the main explanatory variables are themselves strongly
% correlated, particularly VIX and GEPU.
%
% We calculate:
%   1. Correlation matrix on a common complete sample
%   2. VIFs for headline model:
%        Commodity + 2yr spread + VIX
%   3. VIFs for extended model:
%        Commodity + 2yr spread + VIX + GEPU + US GDP


%% 23A. REGRESSOR CORRELATION MATRIX

regressorVars = { ...
    'd_comm_price', ...
    'd_2yr_spread', ...
    'dln_vix', ...
    'dln_gepu', ...
    'd_us_rgdp'};

regressorLabels = { ...
    'Commodity prices', ...
    'AU-US 2yr spread', ...
    'VIX', ...
    'Global EPU', ...
    'US real GDP'};


Xcorr = nan(height(data),length(regressorVars));

for j = 1:length(regressorVars)
    Xcorr(:,j) = data.(regressorVars{j});
end


% Use same 1997Q1 onward sample and require complete observations
validCorr = regSample & all(isfinite(Xcorr),2);

XcorrCommon = Xcorr(validCorr,:);

Rreg = corrcoef(XcorrCommon);


corrRegTable = array2table( ...
    Rreg, ...
    'VariableNames', ...
    matlab.lang.makeValidName(regressorLabels));

corrRegTable = addvars( ...
    corrRegTable, ...
    string(regressorLabels(:)), ...
    'Before',1, ...
    'NewVariableNames','Variable');


disp(' ');
disp('============================================================');
disp('CORRELATION MATRIX AMONG MAIN REGRESSORS');
disp('Common complete sample');
disp('============================================================');
disp(corrRegTable);


writetable( ...
    corrRegTable, ...
    regFile, ...
    'Sheet','regressor_correlations');


%% REGRESSOR CORRELATION HEATMAP

figure('Color','w','Position',[100 100 850 650]);

Hreg = heatmap( ...
    regressorLabels, ...
    regressorLabels, ...
    Rreg);

Hreg.ColorLimits = [-1 1];
Hreg.CellLabelFormat = '%.2f';

Hreg.Title = ...
    'Correlation Matrix of Main AUD Drivers';

exportgraphics( ...
    gcf, ...
    fullfile(figDir,'07_regressor_correlation_heatmap.png'), ...
    'Resolution',300);


%% 23B. VIF: HEADLINE MODEL

headlineVIFVars = { ...
    'd_comm_price', ...
    'd_2yr_spread', ...
    'dln_vix'};

headlineVIFLabels = { ...
    'Commodity', ...
    '2yr spread', ...
    'VIX'};


vifHeadline = calcVIF( ...
    data, ...
    regSample, ...
    headlineVIFVars, ...
    headlineVIFLabels);


disp(' ');
disp('============================================================');
disp('VIFs: HEADLINE MODEL');
disp('Commodity + 2yr spread + VIX');
disp('============================================================');
disp(vifHeadline);


writetable( ...
    vifHeadline, ...
    regFile, ...
    'Sheet','VIF_headline');


%% 23C. VIF: EXTENDED MODEL

extendedVIFVars = { ...
    'd_comm_price', ...
    'd_2yr_spread', ...
    'dln_vix', ...
    'dln_gepu', ...
    'd_us_rgdp'};

extendedVIFLabels = { ...
    'Commodity', ...
    '2yr spread', ...
    'VIX', ...
    'GEPU', ...
    'US GDP'};


vifExtended = calcVIF( ...
    data, ...
    regSample, ...
    extendedVIFVars, ...
    extendedVIFLabels);


disp(' ');
disp('============================================================');
disp('VIFs: EXTENDED MODEL');
disp('Commodity + 2yr spread + VIX + GEPU + US GDP');
disp('============================================================');
disp(vifExtended);


writetable( ...
    vifExtended, ...
    regFile, ...
    'Sheet','VIF_extended');

%% 24. PRE-COVID HEADLINE JOINT REGRESSIONS
%
% Same headline specification:
%
%   AUD change =
%       Commodity
%     + AU-US 2yr spread
%     + VIX
%
% Compare:
%
% Full sample:      1997Q1-2026Q2
% Pre-COVID sample: 1997Q1-2019Q4
%
% This is an important robustness check because COVID created unusually
% large movements in VIX, commodity prices and exchange rates.


preCovidRegSample = ...
    data.quarter_start >= datetime(1997,1,1) & ...
    data.quarter_start <= datetime(2019,10,1);


preCovidResults = table();


for yy = 1:length(yVars)

    %% FULL SAMPLE

    [fullTbl,fullStats] = runHACRegression( ...
        data, ...
        regSample, ...
        yVars{yy}, ...
        headlineVars, ...
        headlineLabels, ...
        nwLags);


    %% PRE-COVID SAMPLE

    [preTbl,preStats] = runHACRegression( ...
        data, ...
        preCovidRegSample, ...
        yVars{yy}, ...
        headlineVars, ...
        headlineLabels, ...
        nwLags);


    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('PRE-COVID ROBUSTNESS: %s\n',yLabels{yy});
    fprintf('============================================================\n');

    fprintf('\nFull 1997Q1-2026Q2:\n');
    disp(fullTbl);

    fprintf('N = %d, R2 = %.3f, Adj R2 = %.3f\n', ...
        fullStats.N,fullStats.R2,fullStats.AdjR2);

    fprintf('\nPre-COVID 1997Q1-2019Q4:\n');
    disp(preTbl);

    fprintf('N = %d, R2 = %.3f, Adj R2 = %.3f\n', ...
        preStats.N,preStats.R2,preStats.AdjR2);


    %% BUILD SIDE-BY-SIDE TABLE

    for j = 2:height(fullTbl)
        % Start at 2 to exclude constant

        thisVar = fullTbl.Variable(j);

        preRow = find(preTbl.Variable == thisVar);

        newRow = table( ...
            string(yLabels{yy}), ...
            thisVar, ...
            fullTbl.Coefficient(j), ...
            fullTbl.HAC_SE(j), ...
            fullTbl.pValue(j), ...
            preTbl.Coefficient(preRow), ...
            preTbl.HAC_SE(preRow), ...
            preTbl.pValue(preRow), ...
            fullStats.N, ...
            preStats.N, ...
            fullStats.R2, ...
            preStats.R2, ...
            'VariableNames', ...
            { ...
            'ExchangeRate', ...
            'Variable', ...
            'Full_Beta', ...
            'Full_HAC_SE', ...
            'Full_pValue', ...
            'PreCOVID_Beta', ...
            'PreCOVID_HAC_SE', ...
            'PreCOVID_pValue', ...
            'Full_N', ...
            'PreCOVID_N', ...
            'Full_R2', ...
            'PreCOVID_R2'});

        preCovidResults = ...
            [preCovidResults; newRow];

    end

end


writetable( ...
    preCovidResults, ...
    regFile, ...
    'Sheet','preCOVID_comparison');

%% 25. SUBSAMPLE STABILITY CHECK
%
% Headline model:
%
%   Commodity + 2yr spread + VIX
%
% We use STANDARDISED coefficients because this makes the relative
% importance of the three variables directly comparable across periods.
%
% Periods:
%
%   1. 1997Q1-2007Q4   Pre-GFC
%   2. 2008Q1-2019Q4   GFC/post-GFC, pre-COVID
%   3. 2020Q1-2026Q2   COVID/recent period
%
% NOTE:
% The third sample is relatively short. Treat this as exploratory.


subsampleNames = { ...
    '1997Q1-2007Q4', ...
    '2008Q1-2019Q4', ...
    '2020Q1-2026Q2'};


subsampleMasks = { ...

    data.quarter_start >= datetime(1997,1,1) & ...
    data.quarter_start <= datetime(2007,10,1), ...

    data.quarter_start >= datetime(2008,1,1) & ...
    data.quarter_start <= datetime(2019,10,1), ...

    data.quarter_start >= datetime(2020,1,1) & ...
    data.quarter_start <= sampleEnd ...
    };


stabilityResults = table();


% Store Real TWI standardised betas for plot
betaSub = nan(length(subsampleNames),length(headlineVars));


for ss = 1:length(subsampleNames)

    sampleMask = subsampleMasks{ss};

    for yy = 1:length(yVars)

        [stdTbl,stdStats] = runStandardisedHACRegression( ...
            data, ...
            sampleMask, ...
            yVars{yy}, ...
            headlineVars, ...
            headlineLabels, ...
            nwLags);


        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('SUBSAMPLE: %s | %s\n', ...
            subsampleNames{ss},yLabels{yy});
        fprintf('============================================================\n');

        disp(stdTbl);

        fprintf('N = %d, R2 = %.3f, Adj R2 = %.3f\n', ...
            stdStats.N,stdStats.R2,stdStats.AdjR2);


        %% SAVE RESULTS

        for jj = 1:height(stdTbl)

            newRow = table( ...
                string(subsampleNames{ss}), ...
                string(yLabels{yy}), ...
                stdTbl.Variable(jj), ...
                stdTbl.StandardisedBeta(jj), ...
                stdTbl.HAC_SE(jj), ...
                stdTbl.tStatistic(jj), ...
                stdTbl.pValue(jj), ...
                stdStats.N, ...
                stdStats.R2, ...
                'VariableNames', ...
                { ...
                'Sample', ...
                'ExchangeRate', ...
                'Variable', ...
                'StandardisedBeta', ...
                'HAC_SE', ...
                'tStatistic', ...
                'pValue', ...
                'N', ...
                'R2'});

            stabilityResults = ...
                [stabilityResults; newRow];

        end


        %% STORE REAL TWI BETAS FOR FIGURE

        if yy == 1

            for jj = 1:length(headlineLabels)

                row = find( ...
                    stdTbl.Variable == headlineLabels{jj});

                betaSub(ss,jj) = ...
                    stdTbl.StandardisedBeta(row);

            end

        end

    end

end


writetable( ...
    stabilityResults, ...
    regFile, ...
    'Sheet','subsample_stability');

%% 26. SUBSAMPLE STABILITY FIGURE - REAL TWI

figure('Color','w','Position',[100 100 950 520]);

bar(betaSub');

grid on;
box off;

xticklabels(headlineLabels);

ylabel('Standardised coefficient');

title( ...
    'Stability of Joint Associations with the Real TWI');


legend( ...
    subsampleNames, ...
    'Location','best');


yline( ...
    0, ...
    'k:', ...
    'HandleVisibility','off');


exportgraphics( ...
    gcf, ...
    fullfile(figDir,'08_subsample_stability_realTWI.png'), ...
    'Resolution',300);

%% ================================================================
% LOCAL FUNCTIONS
%% ================================================================

function y = logdiff100(x)
% 100 times first difference of natural log.
%
% Approximately the quarterly percentage change.

    x = double(x);

    y = nan(size(x));

    y(2:end) = ...
        100 .* (log(x(2:end)) - log(x(1:end-1)));

end


function y = firstdiff(x)
% Ordinary first difference.

    x = double(x);

    y = nan(size(x));

    y(2:end) = x(2:end) - x(1:end-1);

end


function z = zomit(x)
% Standardise a series ignoring missing observations.

    x = double(x);

    mu = mean(x,'omitnan');
    sigma = std(x,'omitnan');

    z = (x-mu)./sigma;

end


function [r,n] = pairCorr(x,y)
% Pearson correlation using pairwise-complete observations.

    valid = ...
        isfinite(x) & ...
        isfinite(y);

    n = sum(valid);

    if n < 3

        r = NaN;
        return;

    end

    xx = x(valid);
    yy = y(valid);

    if std(xx) == 0 || std(yy) == 0

        r = NaN;
        return;

    end

    R = corrcoef(xx,yy);

    r = R(1,2);

end


function [r,n] = leadLagCorr(y,x,h)
% --------------------------------------------------------------
% Corr(y_t, x_{t-h})
%
% h > 0:
%     x leads y
%
% h = 0:
%     contemporaneous
%
% h < 0:
%     x lags y
% --------------------------------------------------------------

    y = double(y);
    x = double(x);

    T = length(y);

    if h > 0

        % Example h = 1:
        % Corr(y_t, x_{t-1})

        yy = y((1+h):T);
        xx = x(1:(T-h));

    elseif h < 0

        k = abs(h);

        % Example h = -1:
        % Corr(y_t, x_{t+1})

        yy = y(1:(T-k));
        xx = x((1+k):T);

    else

        yy = y;
        xx = x;

    end

    [r,n] = pairCorr(xx,yy);

end


function [corrTbl,C,N] = makeLeadLagTable( ...
    T, ...
    sampleMask, ...
    yVar, ...
    xVars, ...
    xLabels, ...
    hVec)

% Construct lead-lag correlation table.

    y = T.(yVar);
    y = y(sampleMask);

    nFactors = length(xVars);
    nHorizons = length(hVec);

    C = nan(nFactors,nHorizons);
    N = nan(nFactors,nHorizons);

    for i = 1:nFactors

        x = T.(xVars{i});
        x = x(sampleMask);

        for j = 1:nHorizons

            h = hVec(j);

            [C(i,j),N(i,j)] = ...
                leadLagCorr(y,x,h);

        end

    end


    % Construct readable column names

    colNames = cell(1,nHorizons);

    for j = 1:nHorizons

        h = hVec(j);

        if h > 0

            colNames{j} = ...
                sprintf('X_leads_%d',h);

        elseif h < 0

            colNames{j} = ...
                sprintf('X_lags_%d',abs(h));

        else

            colNames{j} = 'Contemp';

        end

    end


    corrTbl = array2table( ...
        C, ...
        'VariableNames',colNames);

    corrTbl = addvars( ...
        corrTbl, ...
        string(xLabels(:)), ...
        'Before',1, ...
        'NewVariableNames','Factor');


    % Add contemporaneous sample size

    zeroCol = find(hVec == 0);

    corrTbl.N_contemp = N(:,zeroCol);

end

function [resultTable,stats] = runHACRegression( ...
    T, ...
    sampleMask, ...
    yVar, ...
    xVars, ...
    xLabels, ...
    nwLags)

% ================================================================
% Runs an OLS regression with Newey-West HAC standard errors.
%
% y_t = alpha + beta X_t + error_t
%
% Missing observations are removed jointly.
% ================================================================


y = double(T.(yVar));

K = length(xVars);

X = nan(height(T),K);

for j = 1:K
    X(:,j) = double(T.(xVars{j}));
end


% Common sample
valid = sampleMask & ...
    isfinite(y) & ...
    all(isfinite(X),2);

y = y(valid);
X = X(valid,:);


[beta,se,tval,pval,stats] = ...
    olsNeweyWest(y,X,nwLags);


names = [{'Constant'},xLabels];

resultTable = table( ...
    string(names(:)), ...
    beta, ...
    se, ...
    tval, ...
    pval, ...
    'VariableNames', ...
    {'Variable','Coefficient','HAC_SE','tStatistic','pValue'});

end

function [beta,se,tval,pval,stats] = ...
    olsNeweyWest(y,X,L)

% ================================================================
% OLS WITH NEWEY-WEST HAC STANDARD ERRORS
%
% Inputs:
%   y = T x 1 dependent variable
%   X = T x K regressors WITHOUT intercept
%   L = Newey-West truncation lag
%
% Outputs:
%   beta
%   HAC standard errors
%   t statistics
%   approximate two-sided p values
%   regression statistics
% ================================================================


    y = double(y(:));
    X = double(X);

    T = length(y);

    % Add intercept
    X = [ones(T,1),X];

    K = size(X,2);


    %% OLS

    beta = X \ y;

    u = y - X*beta;


    %% R-SQUARED

    SSE = sum(u.^2);
    SST = sum((y-mean(y)).^2);

    R2 = 1 - SSE/SST;

    AdjR2 = ...
        1 - (1-R2)*(T-1)/(T-K);


    %% NEWEY-WEST LONG-RUN COVARIANCE MATRIX

    S = zeros(K,K);

    % Lag zero
    for t = 1:T

        xt = X(t,:)';

        S = S + ...
            u(t)^2 * (xt*xt');

    end


    % Positive autocovariance lags
    for ell = 1:L

        % Bartlett weight
        w = 1 - ell/(L+1);

        Gamma = zeros(K,K);

        for t = ell+1:T

            xt = X(t,:)';
            xtlag = X(t-ell,:)';

            Gamma = Gamma + ...
                u(t)*u(t-ell) * ...
                (xt*xtlag');

        end

        S = S + w*(Gamma + Gamma');

    end


    %% FINITE-SAMPLE ADJUSTMENT

    S = (T/(T-K)) * S;


    %% HAC COVARIANCE OF BETA

    XXinv = inv(X'*X);

    V = XXinv * S * XXinv;

    se = sqrt(diag(V));


    %% T STATISTICS

    tval = beta ./ se;


    %% APPROXIMATE TWO-SIDED P VALUES
    %
    % Uses normal approximation, appropriate asymptotically.
    % Avoids requiring Statistics Toolbox tcdf().

    pval = erfc(abs(tval)/sqrt(2));


    %% OUTPUT STATISTICS

    stats.N = T;
    stats.K = K;
    stats.R2 = R2;
    stats.AdjR2 = AdjR2;
    stats.SSE = SSE;

end

function vifTable = calcVIF( ...
    T, ...
    sampleMask, ...
    xVars, ...
    xLabels)

% ================================================================
% CALCULATE VARIANCE INFLATION FACTORS
%
% For each regressor j:
%
%     X_j = alpha + other X variables + error
%
%     VIF_j = 1 / (1 - R_j^2)
%
% All VIFs use the SAME complete observation sample.
% ================================================================


K = length(xVars);

X = nan(height(T),K);


for j = 1:K
    X(:,j) = double(T.(xVars{j}));
end


%% COMMON COMPLETE SAMPLE

valid = ...
    sampleMask & ...
    all(isfinite(X),2);

X = X(valid,:);

N = size(X,1);


VIF = nan(K,1);
tolerance = nan(K,1);
R2aux = nan(K,1);


for j = 1:K

    yj = X(:,j);

    other = setdiff(1:K,j);

    Xj = [ones(N,1),X(:,other)];


    %% AUXILIARY REGRESSION

    b = Xj \ yj;

    u = yj - Xj*b;


    SSE = sum(u.^2);
    SST = sum((yj-mean(yj)).^2);


    R2j = 1 - SSE/SST;


    R2aux(j) = R2j;

    tolerance(j) = 1 - R2j;

    VIF(j) = 1/(1-R2j);

end


vifTable = table( ...
    string(xLabels(:)), ...
    VIF, ...
    tolerance, ...
    R2aux, ...
    repmat(N,K,1), ...
    'VariableNames', ...
    { ...
    'Variable', ...
    'VIF', ...
    'Tolerance', ...
    'Auxiliary_R2', ...
    'N'});

end

function [resultTable,stats] = ...
    runStandardisedHACRegression( ...
    T, ...
    sampleMask, ...
    yVar, ...
    xVars, ...
    xLabels, ...
    nwLags)

% ================================================================
% STANDARDISED OLS REGRESSION WITH NEWEY-WEST STANDARD ERRORS
%
% Y and all X variables are standardised to mean 0 and SD 1
% WITHIN THE RELEVANT SAMPLE.
%
% This makes coefficients comparable across variables and periods.
% ================================================================


y = double(T.(yVar));

K = length(xVars);

X = nan(height(T),K);


for j = 1:K
    X(:,j) = double(T.(xVars{j}));
end


%% COMMON COMPLETE SAMPLE

valid = ...
    sampleMask & ...
    isfinite(y) & ...
    all(isfinite(X),2);


y = y(valid);
X = X(valid,:);


%% STANDARDISE Y

y = ...
    (y - mean(y)) ./ ...
    std(y);


%% STANDARDISE X

for j = 1:K

    X(:,j) = ...
        (X(:,j) - mean(X(:,j))) ./ ...
        std(X(:,j));

end


%% HAC REGRESSION

[beta,se,tval,pval,stats] = ...
    olsNeweyWest( ...
    y, ...
    X, ...
    nwLags);


% Drop intercept because after standardisation it should be
% essentially zero and is not of interest.

beta = beta(2:end);
se   = se(2:end);
tval = tval(2:end);
pval = pval(2:end);


resultTable = table( ...
    string(xLabels(:)), ...
    beta, ...
    se, ...
    tval, ...
    pval, ...
    'VariableNames', ...
    { ...
    'Variable', ...
    'StandardisedBeta', ...
    'HAC_SE', ...
    'tStatistic', ...
    'pValue'});

end