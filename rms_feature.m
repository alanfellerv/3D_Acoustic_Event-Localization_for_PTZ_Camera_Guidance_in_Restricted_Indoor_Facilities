function rms_vals = rms_feature(signals)
% RMS_FEATURE  Computes the Root-Mean-Square (RMS) amplitude of one or
%              more signal channels.
%              (Architecture doc block D4: "RMS")
%
%   rms_vals = RMS_FEATURE(signals)
%
%   Input:
%       signals - N x M matrix, one column per channel (or N x 1 for a
%                 single channel)
%
%   Output:
%       rms_vals - 1 x M row vector of RMS values, one per channel
%
%   RMS is a simple energy-level feature: it summarizes how "loud" each
%   channel is over the analysis window, independent of the signal's
%   detailed waveform shape. Used both as a standalone feature and as
%   the building block for ILD.

    rms_vals = sqrt(mean(signals.^2, 1));

end
