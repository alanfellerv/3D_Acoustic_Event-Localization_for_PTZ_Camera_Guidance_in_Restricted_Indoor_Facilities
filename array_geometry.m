function geom = array_geometry()
% ARRAY_GEOMETRY  Microphone array geometry for the 8-mic acoustic DOA system.
%
%   geom = ARRAY_GEOMETRY() returns a struct with:
%       .c               - speed of sound (m/s)
%       .fs              - sampling frequency (Hz)
%       .d_ura           - mic spacing in each plane (m)
%       .r               - 4x3 bottom-plane mic positions (Mic1..Mic4)
%       .array           - phased.URA object for the bottom plane (used by MUSIC)
%       .music_idx       - maps phased.URA element order to Mic1..Mic4 order
%       .d_vert          - vertical spacing between planes (m)
%       .vert_positions  - 4x3 top-plane mic positions (Mic5..Mic8),
%                          Mic(i+4) sits directly above Mic(i)

%% Constants
geom.c  = 343;      % speed of sound (m/s)
geom.fs = 44100;    % sampling frequency (Hz)

%% Bottom plane (z = 0)
geom.d_ura = 0.0464;
d = geom.d_ura;

geom.r = [ d/2   d/2  0;    % Mic1
          -d/2   d/2  0;    % Mic2
          -d/2  -d/2  0;    % Mic3
           d/2  -d/2  0];   % Mic4

geom.array = phased.URA('Size', [2 2], ...
    'ElementSpacing', [d d], ...
    'ArrayNormal', 'z');
geom.array.Element = phased.OmnidirectionalMicrophoneElement( ...
    'FrequencyRange', [20 8000]);

% phased.URA may number its elements differently from Mic1..Mic4 above.
% music_idx(k) is the row of geom.r that matches URA element k, so MUSIC
% can be fed channels in the order the estimator expects.
tb_pos = getElementPosition(geom.array).';
tb_pos = tb_pos - mean(tb_pos, 1);
[found, geom.music_idx] = ismembertol(tb_pos, geom.r, 1e-6, 'ByRows', true);
if ~all(found)
    error('array_geometry:order', ...
        'phased.URA element positions do not match geom.r.');
end

%% Top plane (z = d_vert)
geom.d_vert = d;
geom.vert_positions = geom.r + [0 0 geom.d_vert];   % Mic5..Mic8

end