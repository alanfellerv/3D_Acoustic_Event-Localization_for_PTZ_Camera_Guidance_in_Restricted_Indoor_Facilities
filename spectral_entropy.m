function [H, H_norm] = spectral_entropy(signal, fs)
% SPECTRAL_ENTROPY  Computes the Shannon entropy of a signal's power
%                   spectrum - a measure of how "flat"/noise-like
%                   (high entropy) vs. "peaky"/tonal (low entropy) the
%                   spectral content is.
%                   (Architecture doc block D6: "Spectral Entropy")
%
%   [H, H_norm] = SPECTRAL_ENTROPY(signal, fs)
%
%   Input:
%       signal - N x 1 time-domain signal (single reference channel)
%       fs     - sampling frequency (Hz) (unused in the entropy value
%                itself, kept for interface consistency / future use,
%                e.g. restricting entropy to a specific band)
%
%   Output:
%       H      - raw Shannon entropy (bits), computed on the normalized
%                power spectral density treated as a probability
%                distribution: H = -sum(P.*log2(P))
%       H_norm - H normalized to [0,1] by dividing by log2(numBins),
%                the maximum possible entropy (perfectly flat spectrum)
%
%   Interpretation: broadband noise / an abrupt impact-like event tends
%   toward a flatter spectrum (H_norm closer to 1); a narrowband tone or
%   strongly resonant sound tends toward a peakier spectrum (H_norm
%   closer to 0). Useful as a simple event-type discriminator alongside
%   the DOA estimates.

    signal = signal(:);
    N = length(signal);

    X = abs(fft(signal)).^2;             % power spectrum
    half_N = floor(N/2) + 1;
    X = X(1:half_N);

    P = X / max(sum(X), eps);            % normalize to a probability distribution
    P(P <= 0) = eps;                     % avoid log2(0)

    H = -sum(P .* log2(P));
    H_norm = H / log2(length(P));

end
