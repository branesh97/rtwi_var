function HD = historical_decomposition(phi,e,B);
% %Benjamin Wong
% Monash University
% Edited July 2019
% Calculates the historical decomposition
% 
% INPUTS
% phi             The VAR Coefficient matrix
% e               The VAR residuals
% B              The impact matrix for identification (may be cholesky)
% 
% OUTPUTS
% HD              Stored cell of the historical decomposition


%%
[T N] = size(e);
p = (size(phi,1)-1)/N;

% Get structural shocks from reduced form shocks
ss_shocks = NaN(T,N);
for jj = 1:T
    ss_shocks(jj,:) = inv(B)*e(jj,:)';
end

HD = cell(N,1); %Each cell decomposes a variable

%Companion matrix
F = [phi(2:end,:)';eye(N*(p-1)) zeros(N*(p-1),N)];
bigeye = [eye(N) zeros(N,N*(p-1))];


for jj = 1:T
    % Get impulse response function
    IRF_temp(:,jj) = reshape(bigeye*(F^(jj-1))*bigeye'*B,[],1);
    
    for ii = 1:N %Variables
        for kk = 1:N %shocks
            %weight IRF by realization of  structural shocks
            HD{ii,1}(jj,kk)=dot(IRF_temp((kk-1)*N+ii,:),ss_shocks(jj:-1:1,kk));
            
        end
    end
    
    
    
end


end

