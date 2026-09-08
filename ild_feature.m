function ild_dB = ild_feature(mic_left, mic_right)
% ILD_FEATURE  Computes the Interaural Level Difference (ILD) between a
%              pair of microphone channels, in dB.
%              (Architecture doc block D3: "ILD")
%
%   ild_dB = ILD_FEATURE(mic_left, mic_right)
%
%   Inputs:
%       mic_left, mic_right - N x 1 time-domain signals from two
%                              horizontally-separated microphones
%                              (e.g. Mic1/Mic2 on the ReSpeaker array)
%
%   Output:
%       ild_dB - level difference in dB: positive means the RIGHT
%                channel is louder (source closer to / more aligned
%                with the right mic), negative means LEFT is louder.
%
%   ILD is a classic binaural-hearing cue: a source off to one side is
%   slightly louder at the near-side microphone due to head/array
%   shadowing and the inverse-distance falloff. It's a cheap, fast
%   complementary azimuth cue alongside MUSIC and GCC-PHAT.

    eps_floor = 1e-12;   % avoid log(0)/div-by-0 for near-silent input

    rms_left  = sqrt(mean(mic_left(:).^2))  + eps_floor;
    rms_right = sqrt(mean(mic_right(:).^2)) + eps_floor;

    ild_dB = 20 * log10(rms_right / rms_left);

end
