function [tdoa_est, angle_est_deg, corr, lags] = gcc_phat( ...
    mic_A, mic_B, geom, pair_spacing)

% GCC_PHAT
% Robust GCC-PHAT TDOA estimation for the vertical microphone pair.
%
% mic_A       : reference microphone
% mic_B       : delayed microphone
% geom        : array geometry structure
% pair_spacing: microphone spacing in metres
%
% Outputs:
%   tdoa_est      - estimated TDOA in seconds
%   angle_est_deg - estimated elevation/broadside angle in degrees
%   corr          - GCC-PHAT correlation
%   lags          - correlation lag axis in seconds

%% ---------------------------------------------------------------
% 1. Make signals column vectors
% ---------------------------------------------------------------

mic_A = mic_A(:);
mic_B = mic_B(:);

%% ---------------------------------------------------------------
% 2. Make both signals the same length
% ---------------------------------------------------------------

N = min(length(mic_A), length(mic_B));

mic_A = mic_A(1:N);
mic_B = mic_B(1:N);

%% ---------------------------------------------------------------
% 3. Remove DC
% ---------------------------------------------------------------

mic_A = mic_A - mean(mic_A);
mic_B = mic_B - mean(mic_B);

%% ---------------------------------------------------------------
% 4. Apply a Hann window
% ---------------------------------------------------------------

w = hann(N, 'periodic');

mic_A = mic_A .* w;
mic_B = mic_B .* w;

%% ---------------------------------------------------------------
% 5. FFT
% ---------------------------------------------------------------

Nfft = 2^nextpow2(2*N - 1);

XA = fft(mic_A, Nfft);
XB = fft(mic_B, Nfft);

%% ---------------------------------------------------------------
% 6. Cross-power spectrum
% ---------------------------------------------------------------

G = XB .* conj(XA);

%% ---------------------------------------------------------------
% 7. PHAT weighting
% ---------------------------------------------------------------

G = G ./ (abs(G) + eps);

%% ---------------------------------------------------------------
% 8. Limit GCC-PHAT to useful acoustic band
% ---------------------------------------------------------------
%
% noise_filter.m already uses:
%
%       300 Hz - 3400 Hz
%
% so we use the same useful band here.

f = (0:Nfft-1)' * geom.fs / Nfft;

band_mask = ...
    (f >= 300 & f <= 3400) | ...
    (f >= geom.fs-3400 & f <= geom.fs-300);

G(~band_mask) = 0;

%% ---------------------------------------------------------------
% 9. GCC-PHAT correlation
% ---------------------------------------------------------------

corr_full = ifft(G, 'symmetric');

% Shift zero lag to the centre
corr = fftshift(corr_full);

%% ---------------------------------------------------------------
% 10. Construct lag axis
% ---------------------------------------------------------------

lags = ((-Nfft/2):(Nfft/2-1))' / geom.fs;

% Correct length if Nfft is odd
if length(lags) ~= length(corr)
    lags = ((-floor(Nfft/2)):ceil(Nfft/2)-1)' / geom.fs;
end

%% ---------------------------------------------------------------
% 11. Physical maximum TDOA
% ---------------------------------------------------------------
%
% For two microphones separated by d:
%
%       |tau| <= d/c

max_tdoa = pair_spacing / geom.c;

%% ---------------------------------------------------------------
% 12. Search ONLY inside physically possible TDOA range
% ---------------------------------------------------------------

valid = abs(lags) <= max_tdoa;

corr_valid = abs(corr(valid));
lags_valid = lags(valid);

[~, k_local] = max(corr_valid);

valid_indices = find(valid);
k0 = valid_indices(k_local);

%% ---------------------------------------------------------------
% 13. Parabolic sub-sample interpolation
% ---------------------------------------------------------------

delta = 0;

if k0 > 1 && k0 < length(corr)

    y1 = abs(corr(k0-1));
    y2 = abs(corr(k0));
    y3 = abs(corr(k0+1));

    denom = y1 - 2*y2 + y3;

    if abs(denom) > eps

        delta = 0.5 * (y1 - y3) / denom;

        % Safety limit
        delta = max(min(delta, 0.5), -0.5);

    end
end

%% ---------------------------------------------------------------
% 14. TDOA estimate
% ---------------------------------------------------------------

tdoa_est = lags(k0) + delta / geom.fs;

%% ---------------------------------------------------------------
% 15. Convert TDOA to angle
% ---------------------------------------------------------------

sin_arg = ...
    (geom.c * tdoa_est) / pair_spacing;

% Numerical safety only
sin_arg = max(min(sin_arg, 1), -1);

angle_est_deg = asind(sin_arg);

end