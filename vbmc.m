function [vp,elbo,elbo_sd,exitflag,output,optimState,stats] = vbmc(fun,x0,LB,UB,PLB,PUB,options,varargin)
%VBMC Posterior and model inference via Variational Bayesian Monte Carlo (v0.96)
%   VBMC computes a variational approximation of the full posterior and a 
%   lower bound on the normalization constant (marginal likelhood or model
%   evidence) for a provided unnormalized log posterior.
%
%   VP = VBMC(FUN,X0,LB,UB) initializes the variational posterior in the
%   proximity of X0 (ideally, a posterior mode) and iteratively computes
%   a variational approximation for a given target log posterior FUN.
%   FUN accepts input X and returns the value of the target (unnormalized) 
%   log posterior density at X. LB and UB define a set of strict lower and 
%   upper bounds coordinate vector, X, so that the posterior has support on 
%   LB < X < UB. LB and UB can be scalars or vectors. If scalars, the bound 
%   is replicated in each dimension. Use empty matrices for LB and UB if no 
%   bounds exist. Set LB(i) = -Inf and UB(i) = Inf if the i-th coordinate
%   is unbounded (while other coordinates may be bounded). Note that if LB 
%   and UB contain unbounded variables, the respective values of PLB and PUB
%   need to be specified (see below). VBMC returns a variational posterior
%   solution VP, which can then be manipulated via other functions in the
%   VBMC toolbox (see examples below).
%
%   VP = VBMC(FUN,X0,LB,UB,PLB,PUB) specifies a set of plausible lower and
%   upper bounds such that LB < PLB < PUB < UB. Both PLB and PUB
%   need to be finite. PLB and PUB represent a "plausible" range, which
%   should denote a region of high posterior probability mass. Among other 
%   things, the plausible box is used to draw initial samples and to set 
%   priors over hyperparameters of the algorithm. When in doubt, we found 
%   that setting PLB and PUB using the topmost ~68% percentile range of the 
%   prior (e.g, mean +/- 1 SD for a Gaussian prior) works well in many 
%   cases (but note that additional information might afford a better guess).
%  
%   VP = VBMC(FUN,X0,LB,UB,PLB,PUB,OPTIONS) performs variational inference
%   with the default parameters replaced by values in the structure OPTIONS.
%   VBMC('defaults') returns the default OPTIONS struct.
%  
%   VP = VBMC(FUN,X0,LB,UB,PLB,PUB,OPTIONS,...) passes additional arguments
%   to FUN.
%  
%   VP = VBMC(FUN,VP0,...) uses variational posterior VP0 (from a previous
%   run of VBMC) to initialize the current run. You can leave PLB and PUB
%   empty, in which case they will be set using VP0 (recommended).
%
%   [VP,ELBO] = VBMC(...) returns an estimate of the ELBO, the variational
%   expected lower bound on the log marginal likelihood (log model evidence).
%   This estimate is computed via Bayesian quadrature.
%
%   [VP,ELBO,ELBO_SD] = VBMC(...) returns the standard deviation of the
%   estimate of the ELBO, as computed via Bayesian quadrature. Note that
%   this standard deviation is *not* representative of the error between the 
%   ELBO and the true log marginal likelihood.
%
%   [VP,ELBO,ELBO_SD,EXITFLAG] = VBMC(...) returns an EXITFLAG that describes
%   the exit condition. Possible values of EXITFLAG and the corresponding
%   exit conditions are
%
%    1  Change in the variational posterior, in the ELBO and its uncertainty 
%       have reached a satisfactory level of stability across recent
%       iterations, suggesting convergence of the variational solution.
%    0  Maximum number of function evaluations or iterations reached. Note
%       that the returned solution has *not* stabilized.
%
%   [VP,ELBO,ELBO_SD,EXITFLAG,OUTPUT] = VBMC(...) returns a structure OUTPUT 
%   with the following information:
%          function: <Target probability density function name>
%        iterations: <Total iterations>
%         funccount: <Total function evaluations>
%          bestiter: <Iteration of returned solution>
%      trainsetsize: <Size of training set for returned solution>
%        components: <Number of mixture components of returned solution>
%            rindex: <Reliability index (< 1 is good)>
% convergencestatus: <"probable" or "no" convergence>
%          overhead: <Fractional overhead (total runtime / total fcn time - 1)>
%          rngstate: <Status of random number generator>
%         algorithm: <Variational Bayesian Monte Carlo>
%           message: <VBMC termination message>
%              elbo: <Estimated ELBO for returned solution>
%           elbo_sd: <Estimated standard deviation of ELBO at returned solution>
%           retried: <"yes", "no", or "failed" if a retry run was performed>
%
%   OPTIONS = VBMC('defaults') returns a basic default OPTIONS structure.
%
%   EXITFLAG = VBMC('test') runs a battery of tests. Here EXITFLAG is 0 if
%   everything works correctly.
%
%   Examples:
%     FUN can be a function handle (using @)
%       vp = vbmc(@rosenbrock_test, ...)
%     In this case, F = rosenbrock_test(X) returns the scalar log pdf F of 
%     the target pdf evaluated at X.
%
%     An example with no hard bounds, only plausible bounds
%       plb = [-5 -5]; pub = [5 5]; options.Plot = 'on';
%       [vp,elbo,elbo_sd] = vbmc(@rosenbrock_test,[0 0],[],[],plb,pub,options);
%
%     FUN can also be an anonymous function:
%        lb = [0 0]; ub = [pi 5]; plb = [0.1 0.1]; pub = [3 4]; options.Plot = 'on';
%        vp = vbmc(@(x) 3*sin(x(1))*exp(-x(2)),[1 1],lb,ub,plb,pub,options)
%
%   See VBMC_EXAMPLES for an extended tutorial with more examples. 
%   The most recent version of the algorithm and additional documentation 
%   can be found here: https://github.com/lacerbi/vbmc
%   Also, check out the FAQ: https://github.com/lacerbi/vbmc/wiki
%
%   References: 
%   
%   Acerbi, L. (2018). "Variational Bayesian Monte Carlo". In Advances in 
%   Neural Information Processing Systems 31 (NeurIPS 2018), pp. 8213-8223.
%
%   Acerbi, L. (2019). "An Exploration of Acquisition and Mean Functions in 
%   Variational Bayesian Monte Carlo". In Proc. Machine Learning Research 
%   96: 1-10. 1st Symposium on Advances in Approximate Bayesian Inference, 
%   Montr�al, Canada.
%
%   See also VBMC_EXAMPLES, VBMC_KLDIV, VBMC_MODE, VBMC_MOMENTS, VBMC_PDF, 
%   VBMC_RND, VBMC_DIAGNOSTICS, @.

%--------------------------------------------------------------------------
% VBMC: Variational Bayesian Monte Carlo for posterior and model inference.
% To be used under the terms of the GNU General Public License 
% (http://www.gnu.org/copyleft/gpl.html).
%
%   Author (copyright): Luigi Acerbi, 2018
%   e-mail: luigi.acerbi@{gmail.com,nyu.edu,unige.ch}
%   URL: http://luigiacerbi.com
%   Version: 0.96 (beta)
%   Release date: Nov 20, 2019
%   Code repository: https://github.com/lacerbi/vbmc
%--------------------------------------------------------------------------

% The VBMC interface (such as details of input and output arguments) may 
% undergo minor changes before reaching the stable release (1.0).


%% Start timer

t0 = tic;

%% Basic default options
defopts.Display                 = 'iter         % Level of display ("iter", "notify", "final", or "off")';
defopts.Plot                    = 'off          % Plot marginals of variational posterior at each iteration';
defopts.MaxIter                 = '50*(2+nvars) % Max number of iterations';
defopts.MaxFunEvals             = '50*(2+nvars) % Max number of target fcn evals';
defopts.FunEvalsPerIter         = '5            % Number of target fcn evals per iteration';
defopts.TolStableCount          = '50           % Required stable fcn evals for termination';
defopts.RetryMaxFunEvals        = '0            % Max number of target fcn evals on retry (0 = no retry)';
defopts.MinFinalComponents      = '50           % Number of variational components to refine posterior at termination';

%% If called with no arguments or with 'defaults', return default options
if nargout <= 1 && (nargin == 0 || (nargin == 1 && ischar(fun) && strcmpi(fun,'defaults')))
    if nargin < 1
        fprintf('Basic default options returned (type "help vbmc" for help).\n');
    end
    vp = defopts;
    return;
end

%% If called with one argument which is 'test', run test
if nargout <= 1 && nargin == 1 && ischar(fun) && strcmpi(fun,'test')
    vp = runtest();
    return;
end

%% Advanced options (do not modify unless you *know* what you are doing)

defopts.IntegerVars             = '[]           % Array with indices of integer variables';
defopts.UncertaintyHandling     = 'no           % Explicit noise handling (only partially supported)';
defopts.NoiseSize               = '[]           % Base observation noise magnitude (standard deviation)';
defopts.SpecifyTargetNoise      = 'no           % Target log joint function returns noise estimate (SD) as second output';
defopts.RepeatedObservations    = 'yes          % Allow for repeated measurements at the same location for noisy inputs';
defopts.RepeatedAcqDiscount     = '1            % Multiplicative discount on acquisition fcn to repeat measurement at the same location';
defopts.FunEvalStart            = 'max(D,10)    % Number of initial target fcn evals';
defopts.SGDStepSize             = '0.005        % Base step size for stochastic gradient descent';
defopts.SkipActiveSamplingAfterWarmup   = 'yes  % Skip active sampling the first iteration after warmup';
defopts.RankCriterion           = 'yes          % Use ranking criterion to pick best non-converged solution';
defopts.TolStableEntropyIters   = '6            % Required stable iterations to switch entropy approximation';
defopts.VariableMeans           = 'yes          % Use variable component means for variational posterior';
defopts.VariableWeights         = 'yes          % Use variable mixture weight for variational posterior';
defopts.WeightPenalty           = '0.1          % Penalty multiplier for small mixture weights';
defopts.Diagnostics             = 'off          % Run in diagnostics mode, get additional info';
defopts.OutputFcn               = '[]           % Output function';
defopts.TolStableExcptFrac      = '0.2          % Fraction of allowed exceptions when computing iteration stability';
defopts.Fvals                   = '[]           % Evaluated fcn values at X0';
defopts.OptimToolbox            = '[]           % Use Optimization Toolbox (if empty, determine at runtime)';
defopts.ProposalFcn             = '[]           % Weighted proposal fcn for uncertainty search';
defopts.NonlinearScaling   = 'on                % Automatic nonlinear rescaling of variables';
defopts.SearchAcqFcn       = '@acqfreg_vbmc     % Fast search acquisition fcn(s)';
defopts.NSsearch           = '2^13              % Samples for fast acquisition fcn eval per new point';
defopts.NSent              = '@(K) 100*K        % Total samples for Monte Carlo approx. of the entropy';
defopts.NSentFast          = '0                 % Total samples for preliminary Monte Carlo approx. of the entropy';
defopts.NSentFine          = '@(K) 2^12*K       % Total samples for refined Monte Carlo approx. of the entropy';
defopts.NSentBoost         = '[]                % Total samples for Monte Carlo approx. of the entropy (final boost)';
defopts.NSentFastBoost     = '[]                % Total samples for preliminary Monte Carlo approx. of the entropy (final boost)';
defopts.NSentFineBoost     = '[]                % Total samples for refined Monte Carlo approx. of the entropy (final boost)';
defopts.NSelbo             = '@(K) 50*K         % Samples for fast approximation of the ELBO';
defopts.NSelboIncr         = '0.1               % Multiplier to samples for fast approx. of ELBO for incremental iterations';
defopts.ElboStarts         = '2                 % Starting points to refine optimization of the ELBO';
defopts.NSgpMax            = '80                % Max GP hyperparameter samples (decreases with training points)';
defopts.NSgpMaxWarmup      = '8                 % Max GP hyperparameter samples during warmup';
defopts.NSgpMaxMain        = 'Inf               % Max GP hyperparameter samples during main algorithm';
defopts.WarmupNoImproThreshold = '20 + 5*nvars  % Fcn evals without improvement before stopping warmup';
defopts.WarmupCheckMax     = 'yes               % Also check for max fcn value improvement before stopping warmup';
defopts.StableGPSampling   = '200 + 10*nvars    % Force stable GP hyperparameter sampling (reduce samples or start optimizing)';
defopts.StableGPSamples    = '0                 % Number of GP samples when GP is stable (0 = optimize)';
defopts.GPSampleThin       = '5                 % Thinning for GP hyperparameter sampling';
defopts.GPTrainNinit       = '1024              % Initial design points for GP hyperparameter training';
defopts.GPTrainInitMethod  = 'sobol             % Initial design method for GP hyperparameter training';
defopts.TolGPVar           = '1e-4              % Threshold on GP variance, used to stabilize sampling and by some acquisition fcns';
defopts.gpMeanFun          = 'negquad           % GP mean function';
defopts.KfunMax            = '@(N) N.^(2/3)     % Max variational components as a function of training points';
defopts.Kwarmup            = '2                 % Variational components during warmup';
defopts.AdaptiveK          = '2                 % Added variational components for stable solution';
defopts.HPDFrac            = '0.8               % High Posterior Density region (fraction of training inputs)';
defopts.ELCBOImproWeight   = '3                 % Uncertainty weight on ELCBO for computing lower bound improvement';
defopts.TolLength          = '1e-6              % Minimum fractional length scale';
defopts.CacheSize          = '500               % Size of cache for storing fcn evaluations';
defopts.CacheFrac          = '0.5               % Fraction of search points from starting cache (if nonempty)';
defopts.StochasticOptimizer = 'adam             % Stochastic optimizer for varational parameters';
defopts.TolFunStochastic   = '1e-3              % Stopping threshold for stochastic optimization';
defopts.GPStochasticStepsize = 'off               % Set stochastic optimization stepsize via GP hyperparameters';
defopts.TolSD              = '0.1               % Tolerance on ELBO uncertainty for stopping (iff variational posterior is stable)';
defopts.TolsKL             = '0.01*sqrt(nvars)  % Stopping threshold on change of variational posterior per training point';
defopts.TolStableWarmup    = '15                % Number of stable fcn evals for stopping warmup';
defopts.VariationalSampler = 'malasample        % MCMC sampler for variational posteriors';
defopts.TolImprovement     = '0.01              % Required ELCBO improvement per fcn eval before termination';
defopts.KLgauss            = 'yes               % Use Gaussian approximation for symmetrized KL-divergence b\w iters';
defopts.TrueMean           = '[]                % True mean of the target density (for debugging)';
defopts.TrueCov            = '[]                % True covariance of the target density (for debugging)';
defopts.MinFunEvals        = '5*nvars           % Min number of fcn evals';
defopts.MinIter            = 'nvars             % Min number of iterations';
defopts.HeavyTailSearchFrac = '0.25               % Fraction of search points from heavy-tailed variational posterior';
defopts.MVNSearchFrac      = '0.25              % Fraction of search points from multivariate normal';
defopts.HPDSearchFrac      = '0                 % Fraction of search points from multivariate normal fitted to HPD points';
defopts.SearchCacheFrac    = '0                 % Fraction of search points from previous iterations';
defopts.AlwaysRefitVarPost = 'no                % Always fully refit variational posterior';
defopts.Warmup             = 'on                % Perform warm-up stage';
defopts.WarmupOptions      = '[]                % Special OPTIONS struct for warmup stage';
defopts.StopWarmupThresh   = '0.2               % Stop warm-up when ELCBO increase below threshold (per fcn eval)';
defopts.WarmupKeepThreshold = '20*nvars         % Max log-likelihood difference for points kept after warmup';
defopts.SearchCMAES        = 'on                % Use CMA-ES for search';
defopts.SearchCMAESVPInit  = 'yes               % Initialize CMA-ES search SIGMA from variational posterior';
defopts.MomentsRunWeight   = '0.9               % Weight of previous trials (per trial) for running avg of variational posterior moments';
defopts.GPRetrainThreshold = '1                 % Upper threshold on reliability index for full retraining of GP hyperparameters';
defopts.ELCBOmidpoint      = 'on                % Compute full ELCBO also at best midpoint';
defopts.GPSampleWidths     = '5                 % Multiplier to widths from previous posterior for GP sampling (Inf = do not use previous widths)';
defopts.HypRunWeight       = '0.9               % Weight of previous trials (per trial) for running avg of GP hyperparameter covariance';
defopts.WeightedHypCov     = 'on                % Use weighted hyperparameter posterior covariance';
defopts.TolCovWeight       = '0                 % Minimum weight for weighted hyperparameter posterior covariance';
defopts.GPHypSampler       = 'slicesample       % MCMC sampler for GP hyperparameters';
defopts.CovSampleThresh    = '10                % Switch to covariance sampling below this threshold of stability index';
defopts.DetEntTolOpt       = '1e-3              % Optimality tolerance for optimization of deterministic entropy';
defopts.EntropySwitch      = 'off               % Switch from deterministic entropy to stochastic entropy when reaching stability';
defopts.EntropyForceSwitch = '0.8               % Force switch to stochastic entropy at this fraction of total fcn evals';
defopts.DetEntropyMinD     = '5                 % Start with deterministic entropy only with this number of vars or more';
defopts.TolConLoss         = '0.01              % Fractional tolerance for constraint violation of variational parameters';
defopts.BestSafeSD         = '5                 % SD multiplier of ELCBO for computing best variational solution';
defopts.BestFracBack       = '0.25              % When computing best solution, lacking stability go back up to this fraction of iterations';
defopts.TolWeight          = '1e-2              % Threshold mixture component weight for pruning';
defopts.PruningThresholdMultiplier = '@(K) 1/sqrt(K)   % Multiplier to threshold for pruning mixture weights';
defopts.AnnealedGPMean     = '@(N,NMAX) 0       % Annealing for hyperprior width of GP negative quadratic mean';
defopts.ConstrainedGPMean  = 'no                % Strict hyperprior for GP negative quadratic mean';
defopts.EmpiricalGPPrior   = 'no                % Empirical Bayes prior over some GP hyperparameters';
defopts.InitDesign         = 'plausible         % Initial samples ("plausible" is uniform in the plausible box)';
defopts.gpQuadraticMeanBound = 'yes             % Stricter upper bound on GP negative quadratic mean function';
defopts.Bandwidth          = '0                 % Bandwidth parameter for GP smoothing (in units of plausible box)';
defopts.OutwarpThreshBase  = '10*nvars          % Output warping starting threshold';
defopts.OutwarpThreshMult  = '1.25              % Output warping threshold multiplier when failed sub-threshold check';
defopts.OutwarpThreshTol   = '0.8               % Output warping base threshold tolerance (fraction of current threshold)';
defopts.Temperature        = '1                 % Temperature for posterior tempering (allowed values T = 1,2,3,4)';
defopts.SeparateSearchGP   = 'no                % Use separate GP with constant mean for active search';
defopts.NoiseShaping       = 'no                % Discount observations from from extremely low-density regions';
defopts.NoiseShapingThreshold = '20*nvars       % Threshold from max observed value to start discounting';
defopts.NoiseShapingFactor = '0.2               % Proportionality factor of added noise wrt distance from threshold';
defopts.AcqHedge           = 'no                % Hedge on multiple acquisition functions';
defopts.AcqHedgeIterWindow = '4                 % Past iterations window to judge acquisition fcn improvement';
defopts.AcqHedgeDecay      = '0.9               % Portfolio value decay per function evaluation';
defopts.ActiveVariationalSamples = '0           % MCMC variational steps before each active sampling';
defopts.ActiveSampleFullUpdate = 'no            % Perform GP and variational updates in-between active samples';
defopts.FixedMaxMeanGP     = 'no                % Fix GP quadratic mean function location to max training input';

%% Advanced options for unsupported/untested features (do *not* modify)
defopts.WarpRotoScaling    = 'off               % Rotate and scale input';
%defopts.WarpCovReg         = '@(N) 25/N         % Regularization weight towards diagonal covariance matrix for N training inputs';
defopts.WarpCovReg         = '0                 % Regularization weight towards diagonal covariance matrix for N training inputs';
defopts.WarpNonlinear      = 'off               % Nonlinear input warping';
defopts.WarpEpoch          = '100               % Recalculate warpings after this number of fcn evals';
defopts.WarpMinFun         = '10 + 2*D          % Minimum training points before starting warping';
defopts.WarpNonlinearEpoch = '100               % Recalculate nonlinear warpings after this number of fcn evals';
defopts.WarpNonlinearMinFun = '20 + 5*D         % Minimum training points before starting nonlinear warping';
defopts.ELCBOWeight        = '0                 % Uncertainty weight during ELCBO optimization';
defopts.VarParamsBack      = '0                 % Check variational posteriors back to these previous iterations';
defopts.AltMCEntropy       = 'no                % Use alternative Monte Carlo computation for the entropy';
defopts.VarActiveSample    = 'no                % Variational active sampling';
defopts.FeatureTest        = 'no                % Test a new experimental feature';
defopts.BOWarmup           = 'no                % Bayesian-optimization-like warmup stage';
defopts.gpOutwarpFun       = '[]                % GP default output warping function';

%% If called with 'all', return all default options
if strcmpi(fun,'all')
    vp = defopts;
    return;
end

%% Check that all VBMC subfolders are on the MATLAB path
add2path();

%% Input arguments

if nargin < 3 || isempty(LB); LB = -Inf; end
if nargin < 4 || isempty(UB); UB = Inf; end
if nargin < 5; PLB = []; end
if nargin < 6; PUB = []; end
if nargin < 7; options = []; end

%% Initialize display printing options

if ~isfield(options,'Display') || isempty(options.Display)
    options.Display = defopts.Display;
end

switch lower(options.Display(1:min(end,3)))
    case {'not'}                        % notify
        prnt = 1;
    case {'no','non','off'}             % none
        prnt = 0;
    case {'ite','all','on','yes'}       % iter
        prnt = 3;
    case {'fin','end'}                  % final
        prnt = 2;
    otherwise
        prnt = 3;
end

%% Initialize variables and algorithm structures

if isempty(x0)
    if prnt > 2
        fprintf('X0 not specified. Taking the number of dimensions from PLB and PUB...');
    end
    if isempty(PLB) || isempty(PUB)
        error('vbmc:UnknownDims', ...
            'If no starting point is provided, PLB and PUB need to be specified.');
    end    
    x0 = NaN(size(PLB));
    if prnt > 2
        fprintf(' D = %d.\n', numel(x0));
    end
end

% Initialize from variational posterior
if vbmc_isavp(x0)
    init_from_vp_flag = true;
    vp0 = x0;
    [x0,LB,UB,PLB,PUB,Xvp] = initFromVP(vp0,LB,UB,PLB,PUB,prnt);
else
    init_from_vp_flag = false;    
end
    
D = size(x0,2);     % Number of variables
optimState = [];

% Setup algorithm options
options = setupoptions_vbmc(D,defopts,options);
if options.Warmup
    options_main = options;
    % Use special options during Warmup
    if isfield(options,'WarmupOptions')
        options = setupoptions_vbmc(D,options,options.WarmupOptions);
    end
end

if init_from_vp_flag    % Finish initialization from variational posterior
    x0 = [x0; robustSampleFromVP(vp0,options.FunEvalStart-1,Xvp)];
    clear Xvp vp0;
end

% Check/fix boundaries and starting points
[x0,LB,UB,PLB,PUB] = boundscheck(x0,LB,UB,PLB,PUB,prnt);

% Convert from char to function handles
if ischar(fun); fun = str2func(fun); end

% Setup and transform variables
K = options.Kwarmup;
[vp,optimState] = ...
    setupvars(x0,LB,UB,PLB,PUB,K,optimState,options,prnt);

% Store target density function
optimState.fun = fun;
funwrapper = @(u_) fun(u_,varargin{:});

% Get information from acquisition function(s)
SearchAcqFcn = options.SearchAcqFcn;
for iAcq = 1:numel(SearchAcqFcn)
    try
        % Called with first empty input should return infos
        optimState.acqInfo{iAcq} = SearchAcqFcn{iAcq}([]);
    catch
        optimState.acqInfo{iAcq} = [];
    end
end

% GP struct and GP hyperparameters
gp = [];        hypstruct = [];     hypstruct_search = [];

optimState.gpCovfun = 1;    % Squared exponential kernel with separate length scales
switch optimState.UncertaintyHandlingLevel
    case 0; optimState.gpNoisefun = [1 0];  % Observation noise for stability
    case 1; optimState.gpNoisefun = [1 2];  % Infer noise
    case 2; optimState.gpNoisefun = [1 1];  % Provided heteroskedastic noise
end
if options.NoiseShaping && optimState.gpNoisefun(2) == 0
    optimState.gpNoisefun(2) = 1;
end
optimState.gpMeanfun = options.gpMeanFun;
switch optimState.gpMeanfun
    case {'zero','const','negquad','se','negquadse','negquadfixiso','negquadfix'}
    otherwise
        error('vbmc:UnknownGPmean', ...
            'Unknown/unsupported GP mean function. Supported mean functions are ''zero'', ''const'', ''negquad'', and ''se''.');
end
optimState.gpOutwarpfun = options.gpOutwarpFun;
if ischar(optimState.gpOutwarpfun)
    switch lower(optimState.gpOutwarpfun)
        case {'[]','off','no','none','0'}; optimState.gpOutwarpfun = [];
        otherwise
            optimState.gpOutwarpfun = str2func(optimState.gpOutwarpfun);
    end
end

% Initialize function logger
[~,optimState] = funlogger_vbmc([],D,optimState,'init',options.CacheSize);

if optimState.Cache.active
    displayFormat = ' %5.0f     %5.0f  /%5.0f   %12.2f  %12.2f  %12.2f     %4.0f %10.3g       %s\n';
    displayFormat_warmup = ' %5.0f     %5.0f  /%5.0f   %s\n';
elseif optimState.UncertaintyHandlingLevel > 0
    displayFormat = ' %5.0f       %5.0f %5.0f %12.2f  %12.2f  %12.2f     %4.0f %10.3g     %s\n';
    displayFormat_warmup = ' %5.0f       %5.0f    %12.2f  %s\n';    
else
    displayFormat = ' %5.0f       %5.0f    %12.2f  %12.2f  %12.2f     %4.0f %10.3g     %s\n';
    displayFormat_warmup = ' %5.0f       %5.0f    %12.2f  %s\n';
end
if prnt > 2
    if optimState.Cache.active
        fprintf(' Iteration f-count/f-cache    Mean[ELBO]     Std[ELBO]     sKL-iter[q]   K[q]  Convergence    Action\n');
    else
        if options.BOWarmup
            fprintf(' Iteration   f-count     Max[f]     Action\n');
        elseif optimState.UncertaintyHandlingLevel > 0
            fprintf(' Iteration   f-count (x-count)   Mean[ELBO]     Std[ELBO]     sKL-iter[q]   K[q]  Convergence  Action\n');
        else
            fprintf(' Iteration   f-count     Mean[ELBO]     Std[ELBO]     sKL-iter[q]   K[q]  Convergence  Action\n');            
        end
    end
end

%% Variational optimization loop
iter = 0;
isFinished_flag = false;
exitflag = 0;   output = [];    stats = [];

while ~isFinished_flag
    t_iter = tic;
    timer = timer_init();   % Initialize iteration timer
    
    iter = iter + 1;
    optimState.iter = iter;
    vp_old = vp;
    action = '';
    optimState.redoRotoscaling = false;
    
    if iter == 1 && optimState.Warmup; action = 'start warm-up'; end
    
    % Switch to stochastic entropy towards the end if still on deterministic
    if optimState.EntropySwitch && ...
            optimState.funccount >= options.EntropyForceSwitch*options.MaxFunEvals
        optimState.EntropySwitch = false;
        if isempty(action); action = 'entropy switch'; else; action = [action ', entropy switch']; end        
    end
    
    %% Actively sample new points into the training set
    t = tic;
    optimState.trinfo = vp.trinfo;
    if iter == 1; new_funevals = options.FunEvalStart; else; new_funevals = options.FunEvalsPerIter; end
    if optimState.Xn > 0
        optimState.ymax = max(optimState.y(optimState.X_flag));
    end
    if optimState.SkipActiveSampling
        optimState.SkipActiveSampling = false;
    else        
        if ~isempty(gp) && options.SeparateSearchGP && ~options.VarActiveSample
            % Train a distinct GP for active sampling
            if mod(iter,2) == 0
                meantemp = optimState.gpMeanfun;
                optimState.gpMeanfun = 'const';
                [gp_search,hypstruct_search] = gptrain_vbmc(hypstruct_search,optimState,stats,options);
                optimState.gpMeanfun = meantemp;
            else
                gp_search = gp;                
            end
        else
            gp_search = gp;
        end
        % Performe active sampling
        if options.VarActiveSample
            % FIX TIMER HERE IF USING THIS
            [optimState,vp,t_active,t_func] = ...
                variationalactivesample_vbmc(optimState,new_funevals,funwrapper,vp,vp_old,gp_search,options);
        else
            optimState.hypstruct = hypstruct;
            [optimState,gp,timer] = ...
                activesample_vbmc(optimState,new_funevals,funwrapper,vp,vp_old,gp_search,stats,timer,options);
        end
    end
    optimState.N = optimState.Xn;  % Number of training inputs
    optimState.Neff = sum(optimState.nevals(optimState.X_flag));
    
    %% Input warping / reparameterization (unsupported!)
    if options.WarpNonlinear || options.WarpRotoScaling
        % Beware that the GP here is not updated from active sampling
        t = tic;
        [optimState,vp,hypstruct.hyp,hypstruct.warp,action] = ...
            vbmc_warp(optimState,vp,gp,hypstruct.hyp,hypstruct.warp,action,options);
        timer.warping = timer.warping + toc(t);
    end
                
    %% Train GP
    t = tic;        
    [gp,hypstruct,Ns_gp,optimState] = ...
        gptrain_vbmc(hypstruct,optimState,stats,options);    
    timer.gpTrain = timer.gpTrain + toc(t);
    
    % Check if reached stable sampling regime
    if Ns_gp == options.StableGPSamples && optimState.StopSampling == 0
        optimState.StopSampling = optimState.N;
    end
    
    % Switch to numerical definition of GP mean function
    optimState.gpMeanfun = gp.meanfun;
    
    % Estimate of GP noise around the top high posterior density region
    optimState.sn2hpd = estimate_GPnoise(gp);
    
%     if ~exist('wsabi_hyp','var'); wsabi_hyp = zeros(1,D+1); end    
%     priorMu = (optimState.PLB + optimState.PUB)/2;
%     priorVar = diag(optimState.PUB - optimState.PLB);
%     kernelVar = diag(exp(wsabi_hyp(2:end)));
%     lambda = exp(wsabi_hyp(1));
%     hypVar = [1e4,4*ones(1,D)];    
%     [log_mu,log_Var,~,~,~,wsabi_hyp] = wsabi_oneshot(...
%         'L',priorMu,priorVar,kernelVar,lambda,0.8,gp.X,gp.y,hypVar);
%     log_mu
        
    %% Optimize variational parameters
    t = tic;
    
    if ~vp.optimize_mu  % Variational components fixed to training inputs
        vp.mu = gp.X';
        Knew = size(vp.mu,2);
    else
        % Update number of variational mixture components
        Knew = updateK(optimState,stats,options);
    end
    
    % Decide number of fast/slow optimizations
    Nfastopts = ceil(evaloption_vbmc(options.NSelbo,K));
    
    if optimState.RecomputeVarPost || options.AlwaysRefitVarPost
        Nslowopts = options.ElboStarts; % Full optimizations
        optimState.RecomputeVarPost = false;
    else
        % Only incremental change from previous iteration
        Nfastopts = ceil(Nfastopts * options.NSelboIncr);
        Nslowopts = 1;
    end
    
    % Run optimization of variational parameters
    if optimState.Warmup && options.BOWarmup
        vp_fields = {'elbo','elbo_sd','G','H','varG','varH'};
        for i = 1:numel(vp_fields); vp.stats.(vp_fields{i}) = NaN; end
        varss = NaN;
        pruned = 0;
    else
        [vp,varss,pruned] =  ...
            vpoptimize_vbmc(Nfastopts,Nslowopts,vp,gp,Knew,optimState,options,prnt);        
    end
        
%     % Save variational solution stats
%     vp.stats.elbo = elbo;               % ELBO
%     vp.stats.elbo_sd = elbo_sd;         % Error on the ELBO
%     vp.stats.elogjoint = G;             % Expected log joint
%     vp.stats.elogjoint_sd = sqrt(varG); % Error on expected log joint
%     vp.stats.entropy = H;               % Entropy
%     vp.stats.entropy_sd = sqrt(varH);   % Error on the entropy
%     vp.stats.stable = false;            % Unstable until proven otherwise
    
    optimState.vpK = vp.K;
    optimState.H = vp.stats.entropy;   % Save current entropy
    
    % Get real variational posterior (might differ from training posterior)
    vp_real = vptrain2real(vp,0,options);
    elbo = vp_real.stats.elbo;
    elbo_sd = vp_real.stats.elbo_sd;
    
    timer.variationalFit = timer.variationalFit + toc(t);
    
    %% Recompute warpings at end iteration (unsupported)
    if options.WarpNonlinear || options.WarpRotoScaling
        t = tic;
        [optimState,vp,hypstruct.hyp] = ...
            vbmc_rewarp(optimState,vp,gp,hypstruct.hyp,options);
        timer.warping = timer.warping + toc(t);
    end
    
    %% Plot current iteration (to be improved)
    if options.Plot
        vbmc_iterplot(vp,gp,optimState,stats,elbo);
    end
    
    %mubar
    %Sigma
    
    %----------------------------------------------------------------------
    %% Finalize iteration
    t = tic;
    
    % Compute symmetrized KL-divergence between old and new posteriors
    Nkl = 1e5;
    sKL = max(0,0.5*sum(vbmc_kldiv(vp,vp_old,Nkl,options.KLgauss)));
    
    % Evaluate max LCB of GP prediction on all training inputs
    [~,~,fmu,fs2] = gplite_pred(gp,gp.X,gp.y,gp.s2);
    optimState.lcbmax = max(fmu - options.ELCBOImproWeight*sqrt(fs2));    
        
    % Compare variational posterior's moments with ground truth
    if ~isempty(options.TrueMean) && ~isempty(options.TrueCov) ...
        && all(isfinite(options.TrueMean(:))) ...
        && all(isfinite(options.TrueCov(:)))
    
        [mubar_orig,Sigma_orig] = vbmc_moments(vp_real,1,1e6);
        [kl(1),kl(2)] = mvnkl(mubar_orig,Sigma_orig,options.TrueMean,options.TrueCov);
        sKL_true = 0.5*sum(kl)
    else
        sKL_true = [];
    end
    
    % Record moments in transformed space
    [mubar,Sigma] = vbmc_moments(vp,0);
    if isempty(optimState.RunMean) || isempty(optimState.RunCov)
        optimState.RunMean = mubar(:);
        optimState.RunCov = Sigma;        
        optimState.LastRunAvg = optimState.N;
        % optimState.RunCorrection = 1;
    else
        Nnew = optimState.N - optimState.LastRunAvg;
        wRun = options.MomentsRunWeight^Nnew;
        optimState.RunMean = wRun*optimState.RunMean + (1-wRun)*mubar(:);
        optimState.RunCov = wRun*optimState.RunCov + (1-wRun)*Sigma;
        optimState.LastRunAvg = optimState.N;
        % optimState.RunT = optimState.RunT + 1;
    end
            
    % Check if we are still warming-up
    if optimState.Warmup && iter > 1    
        [optimState,action] = vbmc_warmup(optimState,stats,action,elbo,elbo_sd,options);
        if ~optimState.Warmup
            vp.optimize_mu = logical(options.VariableMeans);
            vp.optimize_weights = logical(options.VariableWeights);
            if options.BOWarmup
                optimState.gpMeanfun = options.gpMeanFun;
                hypstruct.hyp = [];
            end
            % Switch to main algorithm options
            options = options_main;
            hypstruct.runcov = [];    % Reset GP hyperparameter covariance            
        end
    end
    
    % t_fits(iter) = toc(timer_fits);    
    % dt = (t_active(iter)+t_fits(iter))/new_funevals;
    
    timer.finalize = toc(t);
    
    % timer
    
    % Record all useful stats
    stats = savestats(stats, ...
        optimState,vp,elbo,elbo_sd,varss,sKL,sKL_true,gp,hypstruct.full,...
        Ns_gp,pruned,timer,options.Diagnostics);
    
    
    %----------------------------------------------------------------------
    %% Check termination conditions    

    [optimState,stats,isFinished_flag,exitflag,action,msg] = ...
        vbmc_termination(optimState,action,stats,options);
    
    % Check and update output warping threshold
    if ~isempty(optimState.gpOutwarpfun) && (optimState.R < 1)
        Xrnd = vbmc_rnd(vp,1e5);
        ymu = gplite_pred(gp,Xrnd,[],[],1,1);
        ydelta = max([0,optimState.ymax-min(ymu)]);
        if any(ydelta > optimState.OutwarpDelta*options.OutwarpThreshTol) && (optimState.R < 1)
            optimState.OutwarpDelta = optimState.OutwarpDelta*options.OutwarpThreshMult;
        end
    end    
    
    if options.AcqHedge         % Update hedge values        
        optimState.hedge = acqhedge_vbmc('upd',optimState.hedge,stats,options);        
    end    
    
    %% Write iteration output
    
    % vp.w
    
    % Stopped GP sampling this iteration?
    if Ns_gp == options.StableGPSamples && ...
            stats.gpNsamples(max(1,iter-1)) > options.StableGPSamples
        if Ns_gp == 0
            if isempty(action); action = 'switch to GP opt'; else; action = [action ', switch to GP opt']; end
        else
            if isempty(action); action = 'stable GP sampling'; else; action = [action ', stable GP sampling']; end
        end
    end    
    
    if prnt > 2
        if options.BOWarmup && optimState.Warmup
            fprintf(displayFormat_warmup,iter,optimState.funccount,max(optimState.y_orig),action);            
        else
            if optimState.Cache.active
                fprintf(displayFormat,iter,optimState.funccount,optimState.cachecount,elbo,elbo_sd,sKL,vp.K,optimState.R,action);
            elseif optimState.UncertaintyHandlingLevel > 0
                fprintf(displayFormat,iter,optimState.funccount,optimState.N,elbo,elbo_sd,sKL,vp.K,optimState.R,action);                
            else
                fprintf(displayFormat,iter,optimState.funccount,elbo,elbo_sd,sKL,vp.K,optimState.R,action);
            end
        end
    end
            
end

vp_old = vp;

% Pick "best" variational solution to return
[vp,elbo,elbo_sd,idx_best] = ...
    best_vbmc(stats,iter,options.BestSafeSD,options.BestFracBack,options.RankCriterion);
new_final_vp_flag = idx_best ~= iter;

% Last variational optimization with large number of components
[vp,elbo,elbo_sd,changedflag] = finalboost_vbmc(vp,idx_best,optimState,stats,options);
if changedflag; new_final_vp_flag = true; end

if new_final_vp_flag
    if prnt > 2
        % Recompute symmetrized KL-divergence
        sKL = max(0,0.5*sum(vbmc_kldiv(vp,vp_old,Nkl,options.KLgauss)));
        if optimState.UncertaintyHandlingLevel > 0
            fprintf(displayFormat,Inf,optimState.funccount,optimState.N,elbo,elbo_sd,sKL,vp.K,stats.rindex(idx_best),'finalize');
        else
            fprintf(displayFormat,Inf,optimState.funccount,elbo,elbo_sd,sKL,vp.K,stats.rindex(idx_best),'finalize');
        end
    end
end

if ~stats.stable(idx_best); exitflag = 0; end

% Print final message
if prnt > 1
    fprintf('\n%s\n', msg);    
    fprintf('Estimated ELBO: %.3f +/- %.3f.\n', elbo, elbo_sd);
    if exitflag < 1
        fprintf('Caution: Returned variational solution may have not converged.\n');
    end
    fprintf('\n');
end

if nargout > 4
    output = vbmc_output(vp,optimState,msg,stats,idx_best);
    
    % Compute total running time and fractional overhead
    optimState.totaltime = toc(t0);    
    output.overhead = optimState.totaltime / optimState.totalfunevaltime - 1;    
end

if nargout > 6
    % Remove GP from stats struct unless diagnostic run
    if ~options.Diagnostics
        stats = rmfield(stats,'gp');
        stats = rmfield(stats,'gpHypFull');
    end
end

if exitflag < 1 && options.RetryMaxFunEvals > 0
    % Rerun VBMC with better initialization if first try did not work    
    if prnt > 0
        fprintf('First attempt did not converge. Trying to rerun variational optimization.\n');
    end    
    
    % Get better VBMC parameters and initialization from current run
    vp0 = stats.vp(idx_best);
    [x0,LB,UB,PLB,PUB,Xvp] = initFromVP(vp0,LB,UB,PLB,PUB,0);
    Ninit = max(options.FunEvalStart,ceil(options.RetryMaxFunEvals/10));
    x0 = [x0; robustSampleFromVP(vp0,Ninit-1,Xvp)];
    
    options.FunEvalStart = Ninit;
    options.MaxFunEvals = options.RetryMaxFunEvals;
    options.RetryMaxFunEvals = 0;                   % Avoid infinite loop
    options.SGDStepSize = 0.2*options.SGDStepSize;  % Increase stability
    
    try
        [vp,elbo,elbo_sd,exitflag,output2,optimState2,stats] = vbmc(fun,x0,LB,UB,PLB,PUB,options,varargin{:});
        
        if nargout > 4
            optimState2.totaltime = toc(t0);
            output2.overhead = optimState.totaltime / (optimState.totalfunevaltime + optimState2.totalfunevaltime) - 1;
            output2.iterations = output2.iterations + output.iterations;
            output2.funccount = output2.funccount + output.funccount;
            output2.retried = 'yes';
            output = output2;
            optimState = optimState2;
        end        
    catch retryException
        msgText = getReport(retryException);
        warning(msgText);
        if prnt > 0
            fprintf('Attempt of rerunning variational optimization FAILED. Keeping original results.\n');
        end
        if nargout > 4
            output.retried = 'error';
        end
    end
    
else
    if nargout > 4; output.retried = 'no'; end
end



end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function stats = savestats(stats,optimState,vp,elbo,elbo_sd,varss,sKL,sKL_true,gp,hyp_full,Ns_gp,pruned,timer,debugflag)

iter = optimState.iter;
stats.iter(iter) = iter;
stats.N(iter) = optimState.N;
stats.Neff(iter) = optimState.Neff;
stats.funccount(iter) = optimState.funccount;
stats.cachecount(iter) = optimState.cachecount;
stats.vpK(iter) = vp.K;
stats.warmup(iter) = optimState.Warmup;
stats.pruned(iter) = pruned;
stats.elbo(iter) = elbo;
stats.elbo_sd(iter) = elbo_sd;
stats.sKL(iter) = sKL;
if ~isempty(sKL_true)
    stats.sKL_true = sKL_true;
end
stats.gpNoise_hpd(iter) = sqrt(optimState.sn2hpd);
stats.gpSampleVar(iter) = varss;
stats.gpNsamples(iter) = Ns_gp;
stats.gpHypFull{iter} = hyp_full;
stats.timer(iter) = timer;
stats.vp(iter) = vp;
stats.gp(iter) = gplite_clean(gp);
if ~isempty(optimState.gpOutwarpfun)
    stats.outwarp_threshold(iter) = optimState.OutwarpDelta;
else
    stats.outwarp_threshold(iter) = NaN;
end
stats.lcbmax(iter) = optimState.lcbmax;
stats.t(iter) = NaN;    % Fill it at the end of the iteration

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function add2path()
%ADD2PATH Adds VBMC subfolders to MATLAB path.

subfolders = {'acq','ent','gplite','misc','utils'};
% subfolders = {'acq','ent','gplite','misc','utils','warp'};
pathCell = regexp(path, pathsep, 'split');
baseFolder = fileparts(mfilename('fullpath'));

onPath = true;
for iFolder = 1:numel(subfolders)
    folder = [baseFolder,filesep,subfolders{iFolder}];    
    if ispc  % Windows is not case-sensitive
      onPath = onPath & any(strcmpi(folder, pathCell));
    else
      onPath = onPath & any(strcmp(folder, pathCell));
    end
end

% ADDPATH is slow, call it only if folders are not on path
if ~onPath
    addpath(genpath(fileparts(mfilename('fullpath'))));
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [x0,LB,UB,PLB,PUB,Xvp] = initFromVP(vp,LB,UB,PLB,PUB,prnt)

if prnt > 2
    fprintf('Initializing VBMC from variational posterior (D = %d).\n', vp.D);
    if ~isempty(PLB) && ~isempty(PUB)
        fprintf('Using provided plausible bounds. Note that it might be better to leave them empty,\nand allow VBMC to set them using the provided variational posterior.\n');
    end
end

% Find mode in transformed space
x0t = vbmc_mode(vp,[],0);
x0 = warpvars_vbmc(x0t,'inv',vp.trinfo);

% Sample from variational posterior and set plausible bounds accordingly
if isempty(PLB) && isempty(PUB)
    Xvp = vbmc_rnd(vp,1e6,[],1);
    PLB = quantile(Xvp,0.05);
    PUB = quantile(Xvp,0.95);
else
    Xvp = [];
end    
if isempty(LB); LB = vp.trinfo.lb_orig; end
if isempty(UB); UB = vp.trinfo.ub_orig; end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function Xrnd = robustSampleFromVP(vp,Ns,Xrnd,quantile_thresh)
%ROBUSTSAMPLEFROMVP Robust sample from variational posterior.

if nargin < 3; Xrnd = []; end
if nargin < 4 || isempty(quantile_thresh); quantile_thresh = 0.01; end

Ns_big = 1e4;
Xrnd = [Xrnd; vbmc_rnd(vp,max(0,Ns_big-size(Xrnd,1)),[],1)];
Xrnd = Xrnd(1:Ns_big,:);

y = vbmc_pdf(vp,Xrnd);
y_thresh = quantile(y,quantile_thresh);

Xrnd = Xrnd(y > y_thresh,:);
Xrnd = Xrnd(1:Ns,:);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function timer = timer_init()
%TIMER_INIT Initialize iteration timer.

timer.activeSampling = 0;
timer.funEvals = 0;
timer.gpTrain = 0;
timer.variationalFit = 0;
timer.warping = 0;
timer.finalize = 0;

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% TO-DO list:
% - Initialization with multiple (e.g., cell array of) variational posteriors.
% - Combine multiple variational solutions?
% - GP sampling at the very end?
% - Quasi-random sampling from variational posterior (e.g., for initialization).
% - Write a private quantile function to avoid calls to Stats Toolbox.
% - Fix call to fmincon if Optimization Toolbox is not available.
% - Check that I am not using other ToolBoxes by mistake.
