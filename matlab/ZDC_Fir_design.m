%% fir_design_and_golden.m
% ZDC FIR mini-project - Person A
% Designs the 16-tap equiripple low-pass FIR, quantizes it to Q1.15,
% generates the 3 test stimuli, and computes the bit-exact golden outputs.
%
% Outputs (written to the current folder):
%   fir_coeffs.hex            16 lines  - quantized coefficients h[0]..h[15]
%   fir_localparams.txt       ready-to-paste Verilog localparam lines
%   stimulus_case1..3.hex     Ns lines each - input samples (Q1.15)
%   golden_case1..3.hex       Ns lines each - expected y[n] (Q1.15)
%   fig_*.png                 plots for the report

clear; clc; close all;

%% ---------- 1. Parameters ----------
fs       = 48000;            % sampling rate (Hz)
N        = 16;               % number of taps (fixed by the project)
order    = N - 1;            % filter order = taps - 1
fp       = 4000;             % passband edge (Hz)
fst      = 10000;            % stopband edge (Hz)
rip_max  = 1;                % max passband ripple (dB, peak-to-peak)
att_min  = 50;               % min stopband attenuation (dB)

Ns       = 4800;             % samples per test case (agree on this with your teammate!)
amp      = 0.4;              % amplitude of EACH tone (headroom against overflow)
f_wanted = 1000;             % wanted tone (Hz)
f_interf = [18000 7000 3000];% interferer for case 1, 2, 3 (Hz)

%% ---------- 2. Design the filter (Parks-McClellan / equiripple) ----------
% Try increasing stopband weights until BOTH specs are met.
wstop_list = [1 2 3 5 8 10 15 20 30 50 80 100];
found = false;
for wstop = wstop_list
    h = firpm(order, [0 fp fst fs/2]/(fs/2), [1 1 0 0], [1 wstop]);
    [rip, att] = measure_filter(h, fs, fp, fst);
    fprintf('Wstop = %4g -> ripple = %.3f dB, attenuation = %.2f dB\n', wstop, rip, att);
    if rip <= rip_max && att >= att_min
        found = true;
        break;
    end
end
if ~found
    error('No weight in wstop_list met the spec. Extend the list or revisit the spec.');
end
h = h(:);                    % make it a column vector
fprintf('\nChosen Wstop = %g (use Wpass = 1, Wstop = %g in filterDesigner for the screenshots)\n', wstop, wstop);

%% ---------- 3. Quantize to Q1.15 ----------
h_int = round(h * 2^15);     % integer coefficients
assert(all(h_int >= -32768 & h_int <= 32767), 'A coefficient saturates Q1.15!');
h_q = h_int / 2^15;          % the quantized filter, back in real numbers

[rip_q, att_q] = measure_filter(h_q, fs, fp, fst);
fprintf('After quantization: ripple = %.3f dB, attenuation = %.2f dB\n', rip_q, att_q);
if rip_q > rip_max || att_q < att_min
    warning('Quantization pushed the filter out of spec - try a different Wstop.');
end
fprintf('Sum of |h| = %.3f (about 1.31 expected)\n', sum(abs(h_q)));
fprintf('Symmetric coefficients (linear phase)? %d\n', isequal(h_int, flipud(h_int)));

%% ---------- 4. Export the coefficients ----------
write_hex('fir_coeffs.hex', h_int);

fid = fopen('fir_localparams.txt', 'w');
for k = 1:N
    fprintf(fid, 'localparam signed [15:0] H%d = 16''sh%s; // h[%d] = %d\n', ...
        k-1, dec2hex(typecast(int16(h_int(k)), 'uint16'), 4), k-1, h_int(k));
end
fclose(fid);

%% ---------- 5. Test signals + golden model ----------
n = (0:Ns-1)';
X = cell(1,3);  Y = cell(1,3);

for c = 1:3
    % wanted tone + interferer, both at amplitude 'amp'
    x = amp*sin(2*pi*f_wanted*n/fs) + amp*sin(2*pi*f_interf(c)*n/fs);
    x_int = round(x * 2^15);
    assert(all(abs(x_int) <= 32767), 'Stimulus overflows Q1.15 in case %d', c);

    % Golden model = exactly what the RTL computes, in integers:
    %   acc = sum(h_int[k] * x_int[n-k])   (zero initial state = reset delay line)
    %   y   = acc[30:15]  ==  floor(acc / 2^15)   (arithmetic shift right by 15)
    acc   = filter(h_int, 1, x_int);
    y_int = floor(acc / 2^15);
    assert(all(abs(y_int) <= 32767), 'Output overflows Q1.15 in case %d', c);

    write_hex(sprintf('stimulus_case%d.hex', c), x_int);
    write_hex(sprintf('golden_case%d.hex',   c), y_int);

    X{c} = x_int;  Y{c} = y_int;
end

%% ---------- 6. Gain of the quantized filter at the test tones ----------
tones = [f_wanted f_interf];
Hk = freqz(h_q, 1, tones, fs);
fprintf('\nGain of the quantized filter at the test tones:\n');
for k = 1:numel(tones)
    fprintf('  %5d Hz : %7.2f dB\n', tones(k), 20*log10(abs(Hk(k))));
end

%% ---------- 7. Plots for the report ----------
[Hi, f] = freqz(h,   1, 4096, fs);
[Hq, ~] = freqz(h_q, 1, 4096, fs);

figure('Name','Magnitude');
plot(f, 20*log10(abs(Hi)), 'b', f, 20*log10(abs(Hq)), 'r--'); grid on; hold on;
yl = [-100 5]; ylim(yl);
line([fp fp],   yl, 'Color', 'k', 'LineStyle', ':');
line([fst fst], yl, 'Color', 'k', 'LineStyle', ':');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
title('Magnitude response (blue = ideal, red = Q1.15 quantized); dotted = 4 kHz / 10 kHz');
legend('ideal','quantized','Location','southwest');
saveas(gcf, 'fig_magnitude.png');

figure('Name','Phase');
plot(f, unwrap(angle(Hq))*180/pi); grid on;
xlabel('Frequency (Hz)'); ylabel('Phase (degrees)');
title('Phase response (straight line = linear phase)');
saveas(gcf, 'fig_phase.png');

figure('Name','PoleZero');
zplane(h_q.', 1);            % row vector => treated as coefficients
title('Pole/zero plot');
saveas(gcf, 'fig_polezero.png');

figure('Name','Cases');
for c = 1:3
    subplot(3,1,c);
    plot(n(1:200), X{c}(1:200)/2^15, 'b', n(1:200), Y{c}(1:200)/2^15, 'r');
    grid on; ylabel('amplitude');
    title(sprintf('Case %d: 1 kHz + %d kHz  (blue = input, red = golden output)', c, f_interf(c)/1000));
end
xlabel('sample n');
saveas(gcf, 'fig_cases.png');

disp(table((0:N-1)', h, h_int, 'VariableNames', {'k','h_real','h_int'}));
disp('Done. Files written to the current folder.');

%% ---------- Local functions (must stay at the END of the script) ----------
function write_hex(filename, q_int)
    % One 4-digit hex value per line, two's complement, ready for $readmemh.
    fid = fopen(filename, 'w');
    for k = 1:length(q_int)
        fprintf(fid, '%s\n', dec2hex(typecast(int16(q_int(k)), 'uint16'), 4));
    end
    fclose(fid);
end

function [ripple_dB, atten_dB] = measure_filter(h, fs, fp, fst)
    % Passband ripple (peak-to-peak) and stopband attenuation, in dB.
    [H, f] = freqz(h, 1, 8192, fs);
    mag = 20*log10(abs(H) + eps);
    ripple_dB = max(mag(f <= fp)) - min(mag(f <= fp));
    atten_dB  = -max(mag(f >= fst));
end