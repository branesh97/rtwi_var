function BVAR = BVAR_soe(y,p,n_foreign,options)
%% ================================================================
% BVAR_SOE
%
% Bayesian VAR with exact small-open-economy lag restrictions.
%
% The first n_foreign variables form the foreign block:
%
%   Foreign equations:
%       depend only on lags of the foreign variables.
%
%   Domestic equations:
%       depend on lags of ALL variables.
%
% The domestic-to-foreign lag coefficients are therefore EXACTLY zero.
%
%
% MODEL
%
%   y_t = c + A1*y_{t-1} + ... + Ap*y_{t-p} + u_t
%
%   u_t ~ N(0,Sigma)
%
%
% PRIOR
%
% Restricted coefficients:
%
%   beta ~ N(beta0,V0)
%
% with Minnesota-style diagonal prior variance
%
%   Var(beta_{i,j,l})
%
%       = lambda^2
%         / l^(2*decay)
%         * sigma_i^2/sigma_j^2
%
%
% Own first-lag prior mean:
%
%   = 1 if estimated AR(1) >= rw_threshold
%   = 0 otherwise
%
% Intercepts have a diffuse zero-centred prior.
%
%
% Covariance prior:
%
%   Sigma ~ IW(S0,nu0)
%
%
% ESTIMATION
%
% Gibbs sampler:
%
%   beta | Sigma,y  ~ Normal
%
%   Sigma | beta,y  ~ Inverse Wishart
%
% Because equations have different regressors under the SOE
% restriction, the coefficient conditional is calculated as a
% restricted SUR rather than using the standard unrestricted
% matrix-normal formula.
%
%
% INPUTS
%
% y:
%       T x N data matrix
%
% p:
%       VAR lag order
%
% n_foreign:
%       number of variables in foreign block
%
% options:
%       optional structure
%
%       .ndraws             posterior draws retained
%                           default = 5000
%
%       .burnin             burn-in iterations
%                           default = 2000
%
%       .thin               thinning interval
%                           default = 1
%
%       .lambda             Minnesota overall tightness
%                           default = 0.20
%
%       .decay              lag decay exponent
%                           default = 1
%
%       .rw_threshold       AR(1) threshold for prior mean of 1
%                           default = 0.80
%
%       .intercept_var      prior variance of intercept
%                           default = 1e6
%
%       .sigma_df           inverse-Wishart prior df
%                           default = N+2
%
%       .sigma_scale_mult   multiplier on IW prior scale
%                           default = 1
%
%       .stable_only        if true, coefficient draws are restricted
%                           to max companion root < max_root
%                           default = false
%
%       .max_root           stability threshold
%                           default = 0.9999
%
%       .max_stability_tries
%                           maximum rejection attempts per iteration
%                           default = 5000
%
%       .seed               RNG seed
%                           default = 12345
%
%       .store_residuals    save posterior residual draws
%                           default = true
%
%       .verbose            print progress
%                           default = true
%
%
% OUTPUT
%
% BVAR.phi_mean
% BVAR.SIGMA_mean
%
% BVAR.phi_median
% BVAR.SIGMA_median
%
% BVAR.phi_draws
%       (1+p*N) x N x ndraws
%
% BVAR.SIGMA_draws
%       N x N x ndraws
%
% BVAR.e_draws
%       T x N x ndraws
%
% BVAR.root_draws
%
% BVAR.prior
% BVAR.info
% BVAR.X
% BVAR.y
%
%
% COEFFICIENT LAYOUT
%
% Same layout as olsvar / olsvar_soe:
%
%       row 1                 constant
%       rows 2:1+N            lag 1
%       rows 2+N:1+2N         lag 2
%       ...
%
% Forbidden domestic -> foreign coefficients remain exactly zero in
% every posterior draw.
%
%% ================================================================


%% 1. CHECK INPUTS

if nargin < 3

    error( ...
        'BVAR_soe requires y, p and n_foreign.');

end


if nargin < 4 || isempty(options)

    options = struct();

end


[T,N] = ...
    size(y);


if p < 1

    error('p must be at least 1.');

end


if n_foreign < 1 || n_foreign >= N

    error( ...
        'n_foreign must satisfy 1 <= n_foreign < N.');

end


if any(~isfinite(y(:)))

    error('y contains NaN or Inf.');

end


%% 2. OPTIONS

ndraws = ...
    getOption(options,'ndraws',5000);


burnin = ...
    getOption(options,'burnin',2000);


thin = ...
    getOption(options,'thin',1);


lambda = ...
    getOption(options,'lambda',0.20);


decay = ...
    getOption(options,'decay',1);


rw_threshold = ...
    getOption(options,'rw_threshold',0.80);

% Optional explicit own-first-lag prior means.
%
% If empty, fall back to the AR(1) threshold rule.
%
% Example for our AUD system:
%
%   [0 1 0 0 0 0 1]'
%
% means:
%   GDP gaps        -> 0
%   commodity price -> 1
%   VIX             -> 0
%   inflation       -> 0
%   spread          -> 0
%   RTWI            -> 1

own_lag_prior_mean_option = ...
    getOption( ...
    options, ...
    'own_lag_prior_mean', ...
    []);

intercept_var = ...
    getOption(options,'intercept_var',1e6);


sigma_df = ...
    getOption(options,'sigma_df',N+2);


sigma_scale_mult = ...
    getOption(options,'sigma_scale_mult',1);


stable_only = ...
    getOption(options,'stable_only',false);


max_root_allowed = ...
    getOption(options,'max_root',0.9999);


max_stability_tries = ...
    getOption(options,'max_stability_tries',5000);


seed = ...
    getOption(options,'seed',12345);


store_residuals = ...
    getOption(options,'store_residuals',true);


verbose = ...
    getOption(options,'verbose',true);


assert(ndraws >= 1);
assert(burnin >= 0);
assert(thin >= 1);
assert(lambda > 0);
assert(decay >= 0);


if sigma_df <= N+1

    error( ...
        ['sigma_df must exceed N+1 if the inverse-Wishart prior ' ...
         'mean is to exist.']);

end


rng(seed);


%% 3. FULL VAR REGRESSOR MATRIX
%
% Match Ben's olsvar convention:
%
% Backcast the first p observations with the sample mean.


Kfull = ...
    1 + p*N;


y_backcast = [ ...
    repmat(mean(y,1),p,1); ...
    y];


Xfull = ...
    ones(T,Kfull);


for lag = 1:p

    rows = ...
        2 + (lag-1)*N : ...
        1 + lag*N;


    Xfull(:,rows) = ...
        y_backcast( ...
            p+1-lag : ...
            p+T-lag, ...
            :);

end


Y = ...
    y;


%% 4. ALLOWED COEFFICIENTS BY EQUATION
%
% Foreign equations:
%
%   constant
%   + foreign variables at each lag
%
% Domestic equations:
%
%   constant
%   + all variables at each lag


allowedRows = ...
    cell(N,1);


Xeq = ...
    cell(N,1);


for ii = 1:N

    if ii <= n_foreign

        rr = ...
            1;


        for lag = 1:p

            lagRows = ...
                1 + (lag-1)*N + ...
                (1:n_foreign);


            rr = ...
                [rr lagRows];

        end


        allowedRows{ii} = ...
            rr;


    else

        allowedRows{ii} = ...
            1:Kfull;

    end


    Xeq{ii} = ...
        Xfull(:,allowedRows{ii});

end


%% 5. RESTRICTED PARAMETER-VECTOR INDEXING
%
% beta stacks coefficients equation-by-equation.


betaIndex = ...
    cell(N,1);


kEq = ...
    zeros(N,1);


counter = ...
    0;


for ii = 1:N

    kEq(ii) = ...
        length(allowedRows{ii});


    betaIndex{ii} = ...
        counter + ...
        (1:kEq(ii));


    counter = ...
        counter + kEq(ii);

end


Krestricted = ...
    counter;


%% 6. AR(1) CALIBRATION FOR MINNESOTA PRIOR
%
% Use Ben's olsvar if available.
%
% olsvar estimates:
%
%   constant + AR lags
%
% using the same sample-mean backcasting convention.


ar1 = ...
    zeros(N,1);


sigma2 = ...
    zeros(N,1);


for jj = 1:N

    if exist('olsvar','file') == 2

        [phiAR,SigmaAR] = ...
            olsvar( ...
                y(:,jj), ...
                1);


        ar1(jj) = ...
            phiAR(2);


        sigma2(jj) = ...
            SigmaAR;


    else

        % Fallback if olsvar is unavailable

        yj = ...
            y(:,jj);


        yj_ext = [ ...
            mean(yj); ...
            yj];


        Xj = [ ...
            ones(T,1) ...
            yj_ext(1:T)];


        bj = ...
            Xj \ yj;


        ej = ...
            yj - Xj*bj;


        ar1(jj) = ...
            bj(2);


        sigma2(jj) = ...
            (ej'*ej)/(T-2);

    end


    sigma2(jj) = ...
        max(sigma2(jj),1e-8);

end


%% 6A. CHOOSE OWN-FIRST-LAG PRIOR MEANS

if isempty(own_lag_prior_mean_option)

    % Original automatic rule
    ownLagPriorMean = ...
        double(ar1 >= rw_threshold);

else

    ownLagPriorMean = ...
        own_lag_prior_mean_option(:);


    if length(ownLagPriorMean) ~= N

        error( ...
            'options.own_lag_prior_mean must contain N values.');

    end


    if any(~isfinite(ownLagPriorMean))

        error( ...
            'options.own_lag_prior_mean contains invalid values.');

    end

end

%% 7. MINNESOTA PRIOR MEAN AND VARIANCE

beta0 = ...
    zeros(Krestricted,1);


priorVar = ...
    zeros(Krestricted,1);


for ii = 1:N

    idx = ...
        betaIndex{ii};


    rows = ...
        allowedRows{ii};


    for kk = 1:length(rows)

        r = ...
            rows(kk);


        betaPos = ...
            idx(kk);


        %% INTERCEPT

        if r == 1

            beta0(betaPos) = ...
                0;


            priorVar(betaPos) = ...
                intercept_var;


        else

            %% IDENTIFY LAG AND VARIABLE

            lag = ...
                floor((r-2)/N) + 1;


            jj = ...
                mod(r-2,N) + 1;


            %% PRIOR MEAN

            if ...
                    lag == 1 ...
                    && jj == ii

                beta0(betaPos) = ...
                    ownLagPriorMean(ii);

            else

                beta0(betaPos) = ...
                    0;

            end


            %% PRIOR VARIANCE

            priorVar(betaPos) = ...
                lambda^2 ...
                / lag^(2*decay) ...
                * sigma2(ii)/sigma2(jj);

        end

    end

end


% Numerical floor

priorVar = ...
    max(priorVar,1e-12);


V0inv = ...
    diag(1./priorVar);


%% 8. PRIOR FOR SIGMA
%
% E[Sigma] = S0/(nu0-N-1)
%
% Choose S0 so that the prior mean diagonal is approximately the
% univariate AR residual variances.


nu0 = ...
    sigma_df;


S0 = ...
    sigma_scale_mult ...
    * (nu0-N-1) ...
    * diag(sigma2);


%% 9. PRECOMPUTE CROSS PRODUCTS FOR RESTRICTED SUR
%
% Conditional coefficient precision block:
%
%   P_ij
%     = Sigma^{-1}_{ij} * Xi'Xj
%
% Conditional linear term:
%
%   h_i
%     = sum_j Sigma^{-1}_{ij} Xi'y_j


XtX = ...
    cell(N,N);


XtY = ...
    cell(N,N);


for ii = 1:N

    Xi = ...
        Xeq{ii};


    for jj = 1:N

        Xj = ...
            Xeq{jj};


        XtX{ii,jj} = ...
            Xi' * Xj;


        XtY{ii,jj} = ...
            Xi' * Y(:,jj);

    end

end


%% 10. INITIALISE WITH RESTRICTED EQUATION-BY-EQUATION OLS

phiCurrent = ...
    zeros(Kfull,N);


for ii = 1:N

    rows = ...
        allowedRows{ii};


    phiCurrent(rows,ii) = ...
        Xeq{ii} \ Y(:,ii);

end


eCurrent = ...
    Y - Xfull*phiCurrent;


SigmaCurrent = ...
    (eCurrent'*eCurrent)/T;


SigmaCurrent = ...
    makeSPD(SigmaCurrent);


%% 11. STORAGE

phi_draws = ...
    zeros( ...
        Kfull, ...
        N, ...
        ndraws);


SIGMA_draws = ...
    zeros( ...
        N, ...
        N, ...
        ndraws);


if store_residuals

    e_draws = ...
        zeros( ...
            T, ...
            N, ...
            ndraws);

else

    e_draws = [];

end


root_draws = ...
    zeros(ndraws,1);


%% 12. GIBBS SETTINGS

totalIterations = ...
    burnin + ndraws*thin;


saved = ...
    0;


stabilityRejects = ...
    0;


stabilityAttempts = ...
    0;


if verbose

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('BVAR SOE - GIBBS SAMPLER\n');
    fprintf('============================================================\n');

    fprintf('T:                         %d\n',T);
    fprintf('N:                         %d\n',N);
    fprintf('VAR lags:                  %d\n',p);
    fprintf('Foreign variables:         %d\n',n_foreign);

    fprintf('Unrestricted coefficients: %d\n', ...
        Kfull*N);

    fprintf('Allowed coefficients:      %d\n', ...
        Krestricted);

    fprintf('Minnesota lambda:          %.3f\n', ...
        lambda);

    fprintf('Lag decay:                 %.3f\n', ...
        decay);

    fprintf('Posterior draws retained:  %d\n', ...
        ndraws);

    fprintf('Burn-in:                   %d\n', ...
        burnin);

    fprintf('Stable-only posterior:     %d\n', ...
        stable_only);

end


%% 13. GIBBS SAMPLER

for iter = 1:totalIterations

    %% ------------------------------------------------------------
    % 13A. BETA | SIGMA,Y
    %% ------------------------------------------------------------

    SigmaInv = ...
        SigmaCurrent \ eye(N);


    P = ...
        V0inv;


    h = ...
        V0inv*beta0;


    for ii = 1:N

        idx_i = ...
            betaIndex{ii};


        %% Linear term

        for jj = 1:N

            h(idx_i) = ...
                h(idx_i) ...
                + SigmaInv(ii,jj) ...
                * XtY{ii,jj};

        end


        %% Precision blocks

        for jj = 1:N

            idx_j = ...
                betaIndex{jj};


            P(idx_i,idx_j) = ...
                P(idx_i,idx_j) ...
                + SigmaInv(ii,jj) ...
                * XtX{ii,jj};

        end

    end


    % Remove tiny numerical asymmetry

    P = ...
        (P + P')/2;


    Lp = ...
        safeChol(P);


    betaMean = ...
        P \ h;


    %% Draw coefficient vector.
    %
    % If stable_only=true, this samples from the coefficient
    % conditional truncated to the stable VAR region.

    acceptedBeta = ...
        false;


    thisTry = ...
        0;


    while ~acceptedBeta

        thisTry = ...
            thisTry + 1;


        stabilityAttempts = ...
            stabilityAttempts + 1;


        z = ...
            randn(Krestricted,1);


        betaDraw = ...
            betaMean ...
            + (Lp' \ z);


        phiDraw = ...
            restrictedBetaToPhi( ...
                betaDraw, ...
                allowedRows, ...
                betaIndex, ...
                Kfull, ...
                N);


        thisRoot = ...
            maxCompanionRoot( ...
                phiDraw, ...
                p);


        if ...
            ~stable_only ...
            || thisRoot < max_root_allowed

            acceptedBeta = ...
                true;

        else

            stabilityRejects = ...
                stabilityRejects + 1;

        end


        if thisTry >= max_stability_tries

            error( ...
                ['Could not obtain a stable coefficient draw after ' ...
                 '%d attempts at Gibbs iteration %d.'], ...
                max_stability_tries, ...
                iter);

        end

    end


    phiCurrent = ...
        phiDraw;


    %% ------------------------------------------------------------
    % 13B. SIGMA | BETA,Y
    %% ------------------------------------------------------------

    eCurrent = ...
        Y - Xfull*phiCurrent;


    S_post = ...
        S0 ...
        + eCurrent'*eCurrent;


    nu_post = ...
        nu0 + T;


    SigmaCurrent = ...
        drawInverseWishart( ...
            S_post, ...
            nu_post);


    %% ------------------------------------------------------------
    % 13C. STORE POSTERIOR DRAW
    %% ------------------------------------------------------------

    if ...
        iter > burnin ...
        && mod(iter-burnin,thin) == 0

        saved = ...
            saved + 1;


        phi_draws(:,:,saved) = ...
            phiCurrent;


        SIGMA_draws(:,:,saved) = ...
            SigmaCurrent;


        root_draws(saved) = ...
            thisRoot;


        if store_residuals

            e_draws(:,:,saved) = ...
                eCurrent;

        end

    end


    %% ------------------------------------------------------------
    % PROGRESS
    %% ------------------------------------------------------------

    if verbose

        progressStep = ...
            max(1,floor(totalIterations/20));


        if ...
            mod(iter,progressStep) == 0 ...
            || iter == totalIterations

            fprintf( ...
                'Iteration %d of %d; saved %d of %d\n', ...
                iter, ...
                totalIterations, ...
                saved, ...
                ndraws);

        end

    end

end


assert(saved == ndraws);


%% 14. POSTERIOR SUMMARIES

phi_mean = ...
    mean( ...
        phi_draws, ...
        3);


SIGMA_mean = ...
    mean( ...
        SIGMA_draws, ...
        3);


phi_median = ...
    median( ...
        phi_draws, ...
        3);


SIGMA_median = ...
    median( ...
        SIGMA_draws, ...
        3);


e_mean = ...
    Y - Xfull*phi_mean;


e_median = ...
    Y - Xfull*phi_median;


root_mean_phi = ...
    maxCompanionRoot( ...
        phi_mean, ...
        p);


root_median_phi = ...
    maxCompanionRoot( ...
        phi_median, ...
        p);


%% 15. EXACT RESTRICTION CHECK

maxForbiddenCoefficient = ...
    0;


for ii = 1:n_foreign

    forbiddenRows = ...
        [];


    for lag = 1:p

        domesticRows = ...
            1 + (lag-1)*N ...
            + (n_foreign+1:N);


        forbiddenRows = ...
            [forbiddenRows domesticRows];

    end


    thisMax = ...
        max( ...
            abs( ...
                phi_draws( ...
                    forbiddenRows, ...
                    ii, ...
                    :)), ...
            [], ...
            'all');


    maxForbiddenCoefficient = ...
        max( ...
            maxForbiddenCoefficient, ...
            thisMax);

end


assert( ...
    maxForbiddenCoefficient < 1e-14, ...
    'SOE zero restrictions were not preserved exactly.');


%% 16. OUTPUT STRUCTURE

BVAR = struct();


%% Basic model information

BVAR.data = ...
    y;


BVAR.y = ...
    Y;


BVAR.X = ...
    Xfull;


BVAR.T = ...
    T;


BVAR.N = ...
    N;


BVAR.p = ...
    p;


BVAR.n_foreign = ...
    n_foreign;


BVAR.allowedRows = ...
    allowedRows;


BVAR.betaIndex = ...
    betaIndex;


BVAR.Kfull = ...
    Kfull;


BVAR.Krestricted = ...
    Krestricted;


%% Posterior draws

BVAR.phi_draws = ...
    phi_draws;


BVAR.SIGMA_draws = ...
    SIGMA_draws;


BVAR.e_draws = ...
    e_draws;


BVAR.root_draws = ...
    root_draws;


%% Posterior point summaries

BVAR.phi_mean = ...
    phi_mean;


BVAR.SIGMA_mean = ...
    SIGMA_mean;


BVAR.e_mean = ...
    e_mean;


BVAR.phi_median = ...
    phi_median;


BVAR.SIGMA_median = ...
    SIGMA_median;


BVAR.e_median = ...
    e_median;


BVAR.root_mean_phi = ...
    root_mean_phi;


BVAR.root_median_phi = ...
    root_median_phi;


%% Prior information

BVAR.prior = struct();


BVAR.prior.lambda = ...
    lambda;


BVAR.prior.decay = ...
    decay;


BVAR.prior.rw_threshold = ...
    rw_threshold;

BVAR.prior.own_lag_prior_mean = ...
    ownLagPriorMean;


BVAR.prior.intercept_var = ...
    intercept_var;


BVAR.prior.beta0 = ...
    beta0;


BVAR.prior.beta_variance = ...
    priorVar;


BVAR.prior.ar1 = ...
    ar1;


BVAR.prior.sigma2 = ...
    sigma2;


BVAR.prior.S0 = ...
    S0;


BVAR.prior.nu0 = ...
    nu0;


%% Sampling diagnostics

BVAR.info = struct();


BVAR.info.ndraws = ...
    ndraws;


BVAR.info.burnin = ...
    burnin;


BVAR.info.thin = ...
    thin;


BVAR.info.seed = ...
    seed;


BVAR.info.stable_only = ...
    stable_only;


BVAR.info.max_root_allowed = ...
    max_root_allowed;


BVAR.info.stability_attempts = ...
    stabilityAttempts;


BVAR.info.stability_rejects = ...
    stabilityRejects;


if stabilityAttempts > 0

    BVAR.info.stability_rejection_rate = ...
        stabilityRejects ...
        / stabilityAttempts;

else

    BVAR.info.stability_rejection_rate = ...
        0;

end


BVAR.info.maxForbiddenCoefficient = ...
    maxForbiddenCoefficient;


BVAR.info.posterior_root_median = ...
    median(root_draws);


BVAR.info.posterior_root_p95 = ...
    quantile(root_draws,0.95);


BVAR.info.posterior_root_p99 = ...
    quantile(root_draws,0.99);


BVAR.info.posterior_root_max = ...
    max(root_draws);


%% 17. PRINT SUMMARY

if verbose

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('BVAR SOE COMPLETE\n');
    fprintf('============================================================\n');


    fprintf('Posterior mean VAR root:    %.4f\n', ...
        root_mean_phi);


    fprintf('Posterior median VAR root:  %.4f\n', ...
        root_median_phi);


    fprintf('Median draw root:           %.4f\n', ...
        median(root_draws));


    fprintf('95th percentile draw root:  %.4f\n', ...
        quantile(root_draws,0.95));


    fprintf('Maximum draw root:          %.4f\n', ...
        max(root_draws));


    fprintf('Max forbidden coefficient:  %.3e\n', ...
        maxForbiddenCoefficient);


    if stable_only

        fprintf('Stability rejection rate:   %.2f%%\n', ...
            100*BVAR.info.stability_rejection_rate);

    end

end


end


%% ================================================================
% LOCAL FUNCTIONS
%% ================================================================

function value = getOption(options,name,defaultValue)

    if isfield(options,name)

        value = ...
            options.(name);

    else

        value = ...
            defaultValue;

    end

end


function phi = restrictedBetaToPhi( ...
    beta, ...
    allowedRows, ...
    betaIndex, ...
    Kfull, ...
    N)

% Convert the compact restricted coefficient vector into the full
% coefficient matrix used by our VAR / IRF / HD routines.
%
% Forbidden coefficients are zero by construction.


    phi = ...
        zeros(Kfull,N);


    for ii = 1:N

        phi( ...
            allowedRows{ii}, ...
            ii) = ...
            beta(betaIndex{ii});

    end

end


function rootMax = maxCompanionRoot(phi,p)

    Kfull = ...
        size(phi,1);


    N = ...
        size(phi,2);


    assert( ...
        Kfull == 1+p*N);


    Companion = ...
        zeros(N*p,N*p);


    Companion(1:N,:) = ...
        phi(2:end,:)';


    if p > 1

        Companion( ...
            N+1:end, ...
            1:N*(p-1)) = ...
            eye(N*(p-1));

    end


    rootMax = ...
        max(abs(eig(Companion)));

end


function L = safeChol(A)

% Numerically robust lower Cholesky factor.


    A = ...
        (A+A')/2;


    scale = ...
        max( ...
            1, ...
            mean(abs(diag(A))));


    jitter = ...
        0;


    for kk = 1:12

        [L,flag] = ...
            chol( ...
                A + jitter*eye(size(A)), ...
                'lower');


        if flag == 0

            return

        end


        if jitter == 0

            jitter = ...
                1e-12*scale;

        else

            jitter = ...
                10*jitter;

        end

    end


    error('Unable to obtain positive-definite Cholesky factor.');

end


function A = makeSPD(A)

% Remove numerical asymmetry and add the minimum amount of diagonal
% regularisation required for positive definiteness.


    A = ...
        (A+A')/2;


    scale = ...
        max( ...
            1, ...
            mean(abs(diag(A))));


    jitter = ...
        0;


    for kk = 1:12

        [~,flag] = ...
            chol( ...
                A + jitter*eye(size(A)));


        if flag == 0

            A = ...
                A + jitter*eye(size(A));

            return

        end


        if jitter == 0

            jitter = ...
                1e-12*scale;

        else

            jitter = ...
                10*jitter;

        end

    end


    error('Could not regularise matrix to positive definiteness.');

end


function Sigma = drawInverseWishart(S,nu)

% ================================================================
% DRAWINVERSEWISHART
%
% Draw:
%
%       Sigma ~ IW(S,nu)
%
% without requiring iwishrnd / Statistics Toolbox.
%
% Uses the Bartlett decomposition.
%
% nu must be an integer here.
%% ================================================================


    S = ...
        makeSPD(S);


    n = ...
        size(S,1);


    if nu < n

        error( ...
            'Inverse-Wishart df must be >= matrix dimension.');

    end


    if abs(nu-round(nu)) > 1e-12

        error( ...
            ['This self-contained inverse-Wishart sampler assumes ' ...
             'integer degrees of freedom.']);

    end


    nu = ...
        round(nu);


    %% Cholesky factor of inverse scale matrix

    Sinv = ...
        S \ eye(n);


    Sinv = ...
        (Sinv+Sinv')/2;


    L = ...
        safeChol(Sinv);


    %% Bartlett factor
    %
    % A*A' ~ Wishart(I,nu)

    A = ...
        zeros(n);


    for ii = 1:n

        df = ...
            nu - ii + 1;


        % Chi-square(df) generated as sum of squared standard normals.

        A(ii,ii) = ...
            sqrt( ...
                sum( ...
                    randn(df,1).^2));


        if ii > 1

            A(ii,1:ii-1) = ...
                randn(1,ii-1);

        end

    end


    %% Wishart draw with scale inv(S)

    W = ...
        L*A*A'*L';


    W = ...
        (W+W')/2;


    %% Inverse Wishart

    Sigma = ...
        W \ eye(n);


    Sigma = ...
        (Sigma+Sigma')/2;


    Sigma = ...
        makeSPD(Sigma);

end