function [vp,optimState] = setupvars(x0,LB,UB,PLB,PUB,K,optimState,options,prnt)
%INITVARS Initialize variational posterior, transforms and variables for VBMC.

nvars = size(LB,2);

% Starting point
if any(~isfinite(x0))   % Invalid/not provided starting point
    if prnt > 0
        fprintf('Initial starting point is invalid or not provided. Starting from center of plausible region.\n');
    end
    x0 = 0.5*(PLB + PUB);       % Midpoint
end

optimState.LB = LB;
optimState.UB = UB;
optimState.PLB = PLB;
optimState.PUB = PUB;

% Transform variables
trinfo = warpvars(nvars,LB,UB);
trinfo.x0_orig = x0;
if ~isfield(trinfo,'R_mat'); trinfo.R_mat = []; end
if ~isfield(trinfo,'scale'); trinfo.scale = []; end
trinfo.mu = 0.5*(PLB+PUB);
trinfo.delta = PUB-PLB;

% Record starting points (original coordinates)
optimState.Cache.X_orig = x0;
optimState.Cache.y_orig = options.Fvals(:);
if isempty(optimState.Cache.y_orig)
    optimState.Cache.y_orig = NaN(size(optimState.Cache.X_orig,1),1);
end
if size(optimState.Cache.X_orig,1) ~= size(optimState.Cache.y_orig,1)
    error('vbmc:MismatchedStartingInputs',...
        'The number of points in X0 and of their function values as specified in OPTIONS.Fvals are not the same.');
end

x0 = warpvars(x0,'dir',trinfo);

%% Initialize variational posterior

vp.D = nvars;
vp.K = K;
x0start = repmat(x0,[ceil(K/size(x0,1)),1]);
vp.mu = bsxfun(@plus,x0start(1:K,:)',1e-6*randn(vp.D,K));
vp.sigma = 1e-3*ones(1,K);
vp.lambda = ones(vp.D,1);
vp.trinfo = trinfo;
vp.optimize_lambda = true;

optimState.trinfo = vp.trinfo;

% Import prior function evaluations
% if ~isempty(options.FunValues)
%     if ~isfield(options.FunValues,'X') || ~isfield(options.FunValues,'Y')
%         error('bads:funValues', ...
%             'The ''FunValues'' field in OPTIONS needs to have a X and a Y field (respectively, inputs and their function values).');
%     end
%         
%     X = options.FunValues.X;
%     Y = options.FunValues.Y;
%     if size(X,1) ~= size(Y,1)
%         error('X and Y arrays in the OPTIONS.FunValues need to have the same number of rows (each row is a tested point).');        
%     end
%     
%     if ~all(isfinite(X(:))) || ~all(isfinite(Y(:))) || ~isreal(X) || ~isreal(Y)
%         error('X and Y arrays need to be finite and real-valued.');                
%     end    
%     if ~isempty(X) && size(X,2) ~= nvars
%         error('X should be a matrix of tested points with the same dimensionality as X0 (one input point per row).');
%     end
%     if ~isempty(Y) && size(Y,2) ~= 1
%         error('Y should be a vertical array of function values (one function value per row).');
%     end
%     
%     optimState.X = X;
%     optimState.Y = Y;    
%     
%     % Heteroskedastic noise
%     if isfield(options.FunValues,'S')
%         S = options.FunValues.S;
%         if size(S,1) ~= size(Y,1)
%             error('X, Y, and S arrays in the OPTIONS.FunValues need to have the same number of rows (each row is a tested point).');        
%         end    
%         if ~all(isfinite(S)) || ~isreal(S) || ~all(S > 0)
%             error('S array needs to be finite, real-valued, and positive.');
%         end
%         if ~isempty(S) && size(S,2) ~= 1
%             error('S should be a vertical array of estimated function SD values (one SD per row).');
%         end
%         optimState.S = S;        
%     end    
%     
% end

%% Initialize OPTIMSTATE variables

% Maximum value
optimState.ymax = 0;

% Does the starting cache contain function values?
optimState.Cache.active = any(isfinite(optimState.Cache.y_orig));

% When was the last warping action performed (number of training inputs)
optimState.LastWarping = 0;
optimState.LastNonlinearWarping = 0;

% Number of warpings performed
optimState.WarpingCount = 0;
optimState.WarpingNonlinearCount = 0;

% Perform rotoscaling at the end of iteration
optimState.redoRotoscaling = false;

% When GP hyperparameter sampling is switched with optimization
optimState.StopSampling = 0;

% Fully recompute variational posterior
optimState.RecomputeVarPost = true;

% Start with warm-up?
optimState.Warmup = options.Warmup;

% Number of stable iteration of small increment
optimState.WarmupStableIter = 0;

% Proposal function for search
if isempty(options.ProposalFcn)
    optimState.ProposalFcn = @(x) vbmc_proposal(x,optimState.PLB,optimState.PUB);
else
    optimState.ProposalFcn = options.ProposalFcn;
end

% Quality of the variational posterior
optimState.R = Inf;

% Start with adaptive sampling
optimState.SkipAdaptiveSampling = false;

% Running mean and covariance of variational posterior in transformed space
optimState.RunMean = [];
optimState.RunCov = [];
optimState.LastRunAvg = NaN; % Last time running average was updated

% List of points at the end of each iteration
optimState.iterList.u = [];
optimState.iterList.fval = [];
optimState.iterList.fsd = [];
optimState.iterList.fhyp = [];
