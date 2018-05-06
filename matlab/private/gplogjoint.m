function [F,dF,varF,dvarF,varss] = gplogjoint(vp,gp,grad_flags,avg_flag,jacobian_flag,compute_var)
%GPLOGJOINT Expected variational log joint probability via GP approximation

% VP is a struct with the variational posterior
% HYP is the vector of GP hyperparameters: [ell,sf2,sn2,m]
% Note that hyperparameters are already transformed
% X is a N-by-D matrix of training inputs
% Y is a N-by-1 vector of function values at X

if nargin < 3; grad_flags = []; end
if nargin < 4 || isempty(avg_flag); avg_flag = true; end
if nargin < 5 || isempty(jacobian_flag); jacobian_flag = true; end
if nargin < 6; compute_var = []; end
if isempty(compute_var); compute_var = nargout > 2; end

% Check if gradient computation is required
if nargout < 2                              % No 2nd output, no gradients
    grad_flags = 0;
elseif isempty(grad_flags)                  % By default compute all gradients
    grad_flags = 1;
end
if isscalar(grad_flags); grad_flags = ones(1,3)*grad_flags; end

compute_vargrad = nargout > 3 && compute_var && any(grad_flags);

if compute_vargrad && compute_var ~= 2
    error('gplogjoint:FullVarianceGradient', ...
        'Computation of gradient of log joint variance is currently available only for diagonal approximation of the variance.');
end

D = vp.D;           % Number of dimensions
K = vp.K;           % Number of components
N = size(gp.X,1);
mu(:,:) = vp.mu;
sigma(1,:) = vp.sigma;
lambda(:,1) = vp.lambda(:);

Ns = numel(gp.post);            % Hyperparameter samples

if all(gp.meanfun ~= [0 1 4])
    error('gplogjoint:UnsupportedMeanFun', ...
        'Log joint computation currently only supports zero, constant, or negative quadratic mean functions.');
end

% Using negative quadratic mean?
quadratic_meanfun = gp.meanfun == 4;

F = zeros(1,Ns);
% Check which gradients are computed
if grad_flags(1); mu_grad = zeros(D,K,Ns); else, mu_grad = []; end
if grad_flags(2); sigma_grad = zeros(K,Ns); else, sigma_grad = []; end
if grad_flags(3); lambda_grad = zeros(D,Ns); else, lambda_grad = []; end
if compute_var; varF = zeros(1,Ns); end
if compute_vargrad      % Compute gradient of variance?
    if grad_flags(1); mu_vargrad = zeros(D,K,Ns); else, mu_vargrad = []; end
    if grad_flags(2); sigma_vargrad = zeros(K,Ns); else, sigma_vargrad = []; end
    if grad_flags(3); lambda_vargrad = zeros(D,Ns); else, lambda_vargrad = []; end    
end

% varF_diag = zeros(1,Nhyp);

nf = 1 / (2*pi)^(D/2);  % Normalization constant

% Loop over hyperparameter samples
for s = 1:Ns
    hyp = gp.post(s).hyp;
    
    % Extract GP hyperparameters from HYP
    ell = exp(hyp(1:D));
    sf2 = exp(2*hyp(D+1));
    sn2 = exp(2*hyp(D+2));
    
    if gp.meanfun > 0; m0 = hyp(D+3); else; m0 = 0; end
    if quadratic_meanfun
        xm = hyp(D+3+(1:D));
        omega = exp(hyp(2*D+3+(1:D)));        
    end
    
    alpha = gp.post(s).alpha;
    L = gp.post(s).L;
    Lchol = gp.post(s).Lchol;
    sn2_eff = sn2*gp.post(s).sn2_mult;

    for k = 1:K

        tau_k = sqrt(sigma(k)^2*lambda.^2 + ell.^2);
        nf_k = nf / prod(tau_k);  % Covariance normalization factor
        delta_k = bsxfun(@rdivide,bsxfun(@minus, mu(:,k), gp.X'), tau_k);
        z_k = sf2 * nf_k * exp(-0.5 * sum(delta_k.^2,1));    

        F(s) = F(s) + (z_k*alpha + m0)/K;

        if quadratic_meanfun
            nu_k = -0.5*sum(1./omega.^2 .* ...
                (mu(:,k).^2 + sigma(k)^2*lambda.^2 - 2*mu(:,k).*xm + xm.^2),1);            
            F(s) = F(s) + nu_k/K;
        end

        if grad_flags(1)
            dz_dmu = bsxfun(@times, -bsxfun(@rdivide, delta_k, tau_k), z_k);
            mu_grad(:,k,s) = dz_dmu*alpha/K;            
            if quadratic_meanfun
                mu_grad(:,k,s) = mu_grad(:,k,s) - 1./omega.^2.*(mu(:,k) - xm)/K;
            end
            
        end
        
        if grad_flags(2)
            dz_dsigma = bsxfun(@times, sum((lambda./tau_k).^2 .* (delta_k.^2 - 1),1), sigma(k)*z_k); 
            sigma_grad(k,s) = dz_dsigma*alpha/K;
            if quadratic_meanfun
                sigma_grad(k,s) = sigma_grad(k,s) - sigma(k)*sum(1./omega.^2.*lambda.^2,1)/K;
            end            
            
        end

        if grad_flags(3)
            dz_dlambda = bsxfun(@times, (sigma(k)./tau_k).^2 .* (delta_k.^2 - 1), bsxfun(@times,lambda,z_k));
            lambda_grad(:,s) = lambda_grad(:,s) + (dz_dlambda*alpha)/K;
            if quadratic_meanfun
                lambda_grad(:,s) = lambda_grad(:,s) - sigma(k)^2./omega.^2.*lambda/K;
            end            
        end
        
        if compute_var == 2 % Compute only self-variance
            tau_kk = sqrt(2*sigma(k)^2*lambda.^2 + ell.^2);                
            nf_kk = nf / prod(tau_kk);
            if Lchol
                invKzk = (L\(L'\z_k'))/sn2_eff;
            else
                invKzk = -L*z_k';                
            end                
            J_kk = sf2*nf_kk - z_k*invKzk;
            varF(s) = varF(s) + J_kk/K^2;
            
            if compute_vargrad

                if grad_flags(1)
                    mu_vargrad(:,k,s) = -(2*dz_dmu*invKzk)/K^2;
                end

                if grad_flags(2)
                    % sigma_vargrad(k,s) = -2*sigma(k)*nf/prod(tau_kk).^2 -(2*dz_dsigma*invKzk)/K^2;
                    sigma_vargrad(k,s) = -2/K^2*(sf2*sigma(k)*nf_kk*sum(lambda.^2./tau_kk.^2) + dz_dsigma*invKzk);
                end

                if grad_flags(3)
                    lambda_vargrad(:,s) = lambda_vargrad(:,s) - 2/K^2*(sf2*sigma(k)^2*nf_kk.*lambda./tau_kk.^2  + dz_dlambda*invKzk);
                end
                
            end
            
            
        elseif compute_var
            for j = 1:K
                tau_j = sqrt(sigma(j)^2*lambda.^2 + ell.^2);
                nf_j = nf / prod(tau_j);
                delta_j = bsxfun(@rdivide,bsxfun(@minus, mu(:,j), gp.X'), tau_j);
                z_j = sf2 * nf_j * exp(-0.5 * sum(delta_j.^2,1));                    
                
                tau_jk = sqrt((sigma(j)^2 + sigma(k)^2)*lambda.^2 + ell.^2);                
                nf_jk = nf / prod(tau_jk);
                delta_jk = (mu(:,j)-mu(:,k))./tau_jk;
                
                if Lchol
                    J_jk = sf2*nf_jk*exp(-0.5*sum(delta_jk.^2,1)) ...
                     - z_k*(L\(L'\z_j'))/sn2_eff;
                else
                    J_jk = sf2*nf_jk*exp(-0.5*sum(delta_jk.^2,1)) ...
                     + z_k*(L*z_j');                    
                end

                varF(s) = varF(s) + J_jk/K^2;            
            end
            
        end        
        
    end
    

end

if any(grad_flags)
    if grad_flags(1)
        mu_grad = reshape(mu_grad,[D*K,Ns]);
    end
    % Correct for standard log reparameterization of SIGMA
    if jacobian_flag && grad_flags(2)
        sigma_grad = bsxfun(@times,sigma_grad, sigma(:));        
    end
    % Correct for standard log reparameterization of LAMBDA
    if jacobian_flag && grad_flags(3)
        lambda_grad = bsxfun(@times,lambda_grad, lambda(:));        
    end               
    dF = [mu_grad;sigma_grad;lambda_grad];
else
    dF = [];
end

if compute_vargrad
    if grad_flags(1)
        mu_vargrad = reshape(mu_vargrad,[D*K,Ns]);
    end
    % Correct for standard log reparameterization of SIGMA
    if jacobian_flag && grad_flags(2)
        sigma_vargrad = bsxfun(@times,sigma_vargrad, sigma(:));        
    end
    % Correct for standard log reparameterization of LAMBDA
    if jacobian_flag && grad_flags(3)
        lambda_vargrad = bsxfun(@times,lambda_vargrad, lambda(:));        
    end               
    dvarF = [mu_vargrad;sigma_vargrad;lambda_vargrad];
else
    dvarF = [];
end

% [varF; varF_diag]

% Average multiple hyperparameter samples
varss = 0;
if Ns > 1 && avg_flag
    Fbar = sum(F,2)/Ns;
    if compute_var
        varFss = sum((F - Fbar).^2,2)/(Ns-1);     % Estimated variance of the samples
        varss = varFss + std(varF); % Variability due to sampling
        varF = sum(varF,2)/Ns + varFss;
    end
    if compute_vargrad
        dvv = 2*sum(F.*dF,2)/(Ns-1) - 2*Fbar.*sum(dF,2)/(Ns-1);
        dvarF = sum(dvarF,2)/Ns + dvv;
    end
    F = Fbar;
    if any(grad_flags); dF = sum(dF,2)/Ns; end
end


end