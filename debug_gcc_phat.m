%% Diagnostic: verify gccphat + parabolic refinement on a LARGE delay
fs = 44100;
N  = fs;
t  = (0:N-1)'/fs;
rng(1);
x  = randn(N,1);

true_delay = 20/fs;
y = delayseq(x, true_delay, fs);

[tau_est, corr, lags] = gccphat(y, x, fs);
fprintf('--- Large delay sanity check ---\n');
fprintf('True delay: %.6e s (%.2f samples)\n', true_delay, true_delay*fs);
fprintf('Estimated : %.6e s (%.2f samples)\n', tau_est, tau_est*fs);

%% --- Small delay test (matches your ~30 microsecond vertical-pair case) ---
fprintf('\n--- Small delay test (matches your ~30 microsecond vertical-pair case) ---\n');
true_delay_small = 1.3/fs;
y_small = delayseq(x, true_delay_small, fs);

% Coarse (raw gccphat, integer-sample resolution only)
tau_coarse = gccphat(y_small, x, fs);
fprintf('Coarse (no refinement)     -> True: %.3e s | Est: %.3e s\n', true_delay_small, tau_coarse);

% Upsampling approach (previous attempt - shown here to demonstrate the failure mode)
Lup = 8;
y_up = resample(y_small, Lup, 1);
x_up = resample(x, Lup, 1);
tau_up = gccphat(y_up, x_up, fs*Lup);
fprintf('8x upsampled (bad - PHAT)  -> True: %.3e s | Est: %.3e s\n', true_delay_small, tau_up);

% Parabolic sub-sample refinement (current gcc_phat.m approach)
[~, corr_s, lags_s] = gccphat(y_small, x, fs);
[~, k0] = max(abs(corr_s));
y1 = abs(corr_s(k0-1)); y2 = abs(corr_s(k0)); y3 = abs(corr_s(k0+1));
denom = (y1 - 2*y2 + y3);
delta = 0; if denom ~= 0, delta = 0.5*(y1-y3)/denom; end
tau_parab = lags_s(k0) + delta/fs;
fprintf('Parabolic refinement       -> True: %.3e s | Est: %.3e s\n', true_delay_small, tau_parab);