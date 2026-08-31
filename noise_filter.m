function [filtered_signals, vad] = noise_filter(signals, fs, varargin)
% NOISE_FILTER  Band-pass filtering + short-term-energy Voice/Event
%               Activity Detection (VAD), matching the "Audio Acquisition
%               and noise filtering using Band Pass filter, VAD" block in
%               the system architecture.
%
%   filtered_signals = NOISE_FILTER(signals, fs) band-pass filters every
%   column of `signals` (N x M, one column per microphone channel) to the
%   default acoustic-event band [300 3400] Hz using a zero-phase
%   Butterworth filter (filtfilt), then runs frame-based VAD.
%
%   [filtered_signals, vad] = NOISE_FILTER(...) also returns a struct
%   `vad` with fields:
%       .frame_mask     - 1 x NumFrames logical, true = event active
%       .sample_mask    - N x 1 logical, per-sample expansion of frame_mask
%       .active_frames  - indices of frames marked active
%       .active_samples - [first last] sample indices spanning all active
%                         frames (handy for trimming before MUSIC/GCC-PHAT)
%       .frame_energy   - short-term energy per frame (reference channel)
%       .noise_floor    - estimated noise-floor energy
%       .threshold      - energy threshold used for detection
%       .frame_len, .hop, .frame_times - framing parameters / time axis
%
%   Name-Value options:
%       'Band'           - [Flow Fhigh] passband edges in Hz (default [300 3400])
%       'FilterOrder'    - Butterworth filter order (default 4)
%       'FrameLength'    - VAD frame length in samples (default 1024)
%       'HopLength'      - VAD hop length in samples (default 512)
%       'NoiseFrames'    - number of leading frames assumed noise-only,
%                          used to estimate the noise floor (default 5)
%       'ThresholdDB'    - dB above noise floor to declare activity (default 6)
%       'HangoverFrames' - extra frames kept "active" after energy drops,
%                          avoids choppy on/off detection (default 2)
%       'RefChannel'     - which channel(s) drive the VAD energy:
%                          'mean' (default, averages across channels) or
%                          a channel index
%
%   Note: filtering is applied identically (same b,a, same filtfilt call)
%   to every channel, so the relative inter-channel phase/delay that
%   MUSIC and GCC-PHAT depend on is preserved - this is why filtfilt
%   (zero-phase) is used instead of a causal IIR filter, which would
%   otherwise distort the delay estimates.

    %% --- Parse options ---
    p = inputParser;
    addParameter(p, 'Band',            [300 3400]);
    addParameter(p, 'FilterOrder',     4);
    addParameter(p, 'FrameLength',     1024);
    addParameter(p, 'HopLength',       512);
    addParameter(p, 'NoiseFrames',     5);
    addParameter(p, 'ThresholdDB',     6);
    addParameter(p, 'HangoverFrames',  2);
    addParameter(p, 'RefChannel',      'mean');
    parse(p, varargin{:});
    opt = p.Results;

    [N, M] = size(signals);

    %% --- Band-pass filter (zero-phase Butterworth) ---
    nyq = fs/2;
    Wn  = opt.Band / nyq;
    Wn  = min(max(Wn, 1e-6), 0.999);   % safety clip inside (0,1)
    [b, a] = butter(opt.FilterOrder, Wn, 'bandpass');

    filtered_signals = zeros(N, M);
    for m = 1:M
        filtered_signals(:, m) = filtfilt(b, a, signals(:, m));
    end

    %% --- Voice/Event Activity Detection (short-term energy) ---
    frame_len  = opt.FrameLength;
    hop        = opt.HopLength;
    num_frames = floor((N - frame_len) / hop) + 1;

    if ischar(opt.RefChannel) && strcmpi(opt.RefChannel, 'mean')
        ref_signal = mean(filtered_signals, 2);
    else
        ref_signal = filtered_signals(:, opt.RefChannel);
    end

    frame_energy = zeros(1, num_frames);
    frame_times  = zeros(1, num_frames);
    for k = 1:num_frames
        idx = (k-1)*hop + (1:frame_len);
        frame_energy(k) = sum(ref_signal(idx).^2) / frame_len;
        frame_times(k)  = (idx(1)-1) / fs;
    end

    %% --- Noise floor + threshold ---
    noise_frames = min(opt.NoiseFrames, num_frames);
    noise_floor  = mean(frame_energy(1:noise_frames));
    threshold    = noise_floor * 10^(opt.ThresholdDB/10);

    raw_mask = frame_energy > threshold;

    %% --- Hangover smoothing (avoid choppy on/off detection) ---
    frame_mask = raw_mask;
    hang = 0;
    for k = 1:num_frames
        if raw_mask(k)
            hang = opt.HangoverFrames;
        elseif hang > 0
            frame_mask(k) = true;
            hang = hang - 1;
        end
    end

    %% --- Expand frame-level mask to sample-level ---
    sample_mask = false(N, 1);
    for k = 1:num_frames
        if frame_mask(k)
            idx = (k-1)*hop + (1:frame_len);
            sample_mask(idx) = true;
        end
    end

    active_idx = find(sample_mask);
    if isempty(active_idx)
        active_samples = [1 N];   % fallback: no activity detected, keep all
    else
        active_samples = [active_idx(1) active_idx(end)];
    end

    %% --- Package outputs ---
    vad.frame_mask     = frame_mask;
    vad.sample_mask     = sample_mask;
    vad.active_frames   = find(frame_mask);
    vad.active_samples  = active_samples;
    vad.frame_energy    = frame_energy;
    vad.noise_floor      = noise_floor;
    vad.threshold        = threshold;
    vad.frame_len        = frame_len;
    vad.hop              = hop;
    vad.frame_times      = frame_times;
    vad.filter_b         = b;
    vad.filter_a         = a;

end