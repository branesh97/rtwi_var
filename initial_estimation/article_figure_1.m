%% ================================================================
%  AUSTRALIAN DOLLAR ARTICLE FIGURES
%
%  Figure 1:
%  Real TWI with major historical episodes shaded
%
%  Sample: 1995Q1 - 2026Q2
%% ================================================================

clear;
clc;
close all;


%% 1. PRELIMINARY

folder = fileparts(mfilename('fullpath'));

filePath = ...
    fullfile(folder,'data','data_collected.xlsx');


% Separate folder for article-ready figures
figDir = ...
    fullfile(folder,'figures','article');

if ~exist(figDir,'dir')
    mkdir(figDir);
end


%% 2. IMPORT DATA

data = readtable( ...
    filePath, ...
    'Sheet','data', ...
    'VariableNamingRule','preserve');


data = standardizeMissing( ...
    data, ...
    {'NA','N/A','na',''});


%% 3. MAKE SURE DATES ARE DATETIME

dateVars = { ...
    'quarter_start', ...
    'quarter_end'};


for ii = 1:length(dateVars)

    v = ...
        dateVars{ii};

    if ~isdatetime(data.(v))

        if isnumeric(data.(v))

            data.(v) = ...
                datetime( ...
                    data.(v), ...
                    'ConvertFrom','excel');

        else

            data.(v) = ...
                datetime(data.(v));

        end

    end

end


%% 4. YEARLAB
%
% Same convention used throughout our SVAR/BVAR work:
%
% 1995Q1 = 1995.00
% 1995Q2 = 1995.25
% 1995Q3 = 1995.50
% 1995Q4 = 1995.75

yr = ...
    year(data.quarter_start);

qtr = ...
    ceil(month(data.quarter_start)/3);


yearlab = ...
    yr + (qtr-1)/4;


%% 5. ARTICLE SAMPLE

sampleStart = ...
    datetime(1995,1,1);

sampleEnd = ...
    datetime(2026,4,1);     % 2026Q2


sample = ...
    data.quarter_start >= sampleStart & ...
    data.quarter_start <= sampleEnd;


D = ...
    data(sample,:);

x = ...
    yearlab(sample);

rtwi = ...
    D.rtwi;


assert(height(D) == 126, ...
    'Unexpected sample length.');

assert(all(isfinite(rtwi)), ...
    'RTWI contains missing observations.');


%% REAL TWI WITH SHADED HISTORICAL EPISODES
% Put this in article_figures.m

%% 1. SET UP FIGURE DATA

% x should already be your decimal-year or quarterly time axis
% rtwi should already be the real TWI series

% Example episode dates:
% GFC                    : 2008Q3 to 2009Q2
% Commodity boom         : 2010Q4 to 2011Q4
% Post-boom              : 2012Q4 to 2015Q2
% COVID shock            : 2020Q1 to 2020Q2
% COVID rebound          : 2020Q3 to 2021Q2
% Recent period / 2022-26: 2022Q1 to 2026Q2

episodeNames = { ...
    'GFC', ...
    'Boom', ...
    'Post-boom', ...
    'COVID shock', ...
    'Rebound', ...
    '2022-26'};

episodeX0 = [ ...
    2008.50, ...
    2010.75, ...
    2012.75, ...
    2020.00, ...
    2020.50, ...
    2022.00];

episodeX1 = [ ...
    2009.50, ...
    2011.50, ...
    2015.50, ...
    2020.25, ...
    2021.50, ...
    2026.25];

nEpisodes = numel(episodeNames);

%% 2. AXIS LIMITS

ymin = min(rtwi);
ymax = max(rtwi);
yrange = ymax - ymin;

ylow  = ymin - 0.04*yrange;
yhigh = ymax + 0.10*yrange;

%% 3. CREATE FIGURE

figure('Color','w','Position',[100 100 1500 700]);
hold on;

%% 4. SHADED REGIONS

shadeColour = [0.87 0.87 0.87];   % lighter grey

for ee = 1:nEpisodes
    patch( ...
        [episodeX0(ee) episodeX1(ee) episodeX1(ee) episodeX0(ee)], ...
        [ylow ylow yhigh yhigh], ...
        shadeColour, ...
        'FaceAlpha',0.35, ...
        'EdgeColor','none', ...
        'HandleVisibility','off');
end

%% 5. PLOT RTWI

plot(x, rtwi, '-k', 'LineWidth', 2.8, 'HandleVisibility','off');

%% 6. LABEL POSITIONS
% Stagger vertically and add small horizontal nudges where needed

labelX = (episodeX0 + episodeX1)/2;

% horizontal nudges to reduce crowding
labelX(1) = labelX(1) - 0.10;   % GFC a bit left
labelX(2) = labelX(2) + 0.10;   % Commodity boom a bit right
labelX(3) = labelX(3) + 0.00;   % Post-boom
labelX(4) = labelX(4) + 0.00;   % COVID shock
labelX(5) = labelX(5) + 0.10;   % COVID rebound
labelX(6) = labelX(6) + 0.00;   % 2022-26

labelY = [ ...
    ymax + 0.040*yrange, ...
    ymax + 0.058*yrange, ...
    ymax + 0.040*yrange, ...
    ymax - 0.005*yrange, ...
    ymax + 0.040*yrange, ...
    ymax + 0.040*yrange];

labelRotation = [0 0 0 90 0 0];

%% 7. ADD EPISODE LABELS

for ee = 1:nEpisodes
    text( ...
        labelX(ee), ...
        labelY(ee), ...
        episodeNames{ee}, ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', ...
        'Rotation',labelRotation(ee), ...
        'FontSize',10.5, ...
        'FontWeight','bold', ...
        'Color',[0.15 0.15 0.15], ...
        'Clipping','on');
end

%% 8. FORMATTING

xlim([1995 2026.5]);
ylim([ylow yhigh]);

xticks(1995:5:2025);

%xlabel('Year', 'FontSize', 13);
ylabel('Real trade-weighted index (RTWI)', 'FontSize', 15);

%title('The Australian Dollar Through Changing Economic Environments', ...
%    'FontSize',16, 'FontWeight','bold');

grid on;
box off;

set(gca, ...
    'FontSize',12, ...
    'Layer','top', ...
    'TickDir','out');

ax = gca;
ax.GridAlpha = 0.12;
ax.XMinorGrid = 'off';
ax.YMinorGrid = 'off';

% High-quality vector version for Canva
print( ...
    gcf, ...
    fullfile(figDir,'figure1_rtwi_article.svg'), ...
    '-dsvg');

%% 9. EXPORT

exportgraphics(gcf, ...
    fullfile(figDir,'01_rtwi_historical_episodes.png'), ...
    'Resolution',300);

exportgraphics(gcf, ...
    fullfile(figDir,'01_rtwi_historical_episodes.pdf'), ...
    'ContentType','vector');

fprintf('\nArticle figure saved to:\n%s\n', figDir);