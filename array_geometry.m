function geom = array_geometry()
% ARRAY_GEOMETRY  Defines microphone array geometry for the acoustic DOA system.
%
%   geom = ARRAY_GEOMETRY() returns a struct containing:
%       .c            - speed of sound (m/s)
%       .fs           - sampling frequency (Hz)
%       .d_ura        - ReSpeaker Quad mic spacing (m)
%       .r             - 4x3 matrix of ReSpeaker mic positions (x,y,z)
%       .array         - phased.URA object for the ReSpeaker Quad array
%       .d_vert        - vertical INMP441 pair spacing (m)
%       .vert_positions - 2x3 matrix of vertical pair mic positions

%% --- Constants ---
geom.c  = 343;      % speed of sound (m/s)
geom.fs = 44100;    % sampling frequency (Hz)

%% --- ReSpeaker Quad HAT (square array, 4 MEMS mics via AC108 codec) ---
geom.d_ura = 0.0464;   % mic spacing (m) - update to match datasheet if different

d = geom.d_ura;
geom.r = [ d/2   d/2  0;   % Mic1
    -d/2   d/2  0;   % Mic2
    -d/2  -d/2  0;   % Mic3
    d/2  -d/2  0];  % Mic4

% Uniform Rectangular Array object for phased.MUSICEstimator2D
geom.array = phased.URA('Size', [2 2], ...
    'ElementSpacing', [geom.d_ura geom.d_ura], ...
    'ArrayNormal', 'z');
geom.array.Element = phased.OmnidirectionalMicrophoneElement( ...
    'FrequencyRange', [20 8000]);

%% --- Vertical INMP441 Pair (independent of ReSpeaker array) ---
geom.d_vert = 0.05;   % vertical mic spacing (m) - update to actual hardware spacing
geom.vert_positions = [0 0 0; 0 0 geom.d_vert];

end