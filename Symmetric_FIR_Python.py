import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from scipy.signal import convolve

def find_3dB_cutoff(freqs, mag_db):
    target = -3.0

    idx = np.where(mag_db <= target)[0]
    if len(idx) == 0:
        return None

    i = idx[0]
    if i == 0:
        return freqs[0]

    f1, f2 = freqs[i - 1], freqs[i]
    m1, m2 = mag_db[i - 1], mag_db[i]

    # interpolate to -3 dB
    cutoff = f1 + (target - m1) * (f2 - f1) / (m2 - m1)
    return cutoff

def find_zero_crossings(sample):
    signs = np.sign(sample)
    zero_crossings = np.where(np.diff(signs) != 0)[0]
    return zero_crossings

def find_stopband_start(freqs, mag_db, threshold=-40):
    idx = np.where(mag_db <= threshold)[0]
    if len(idx) == 0:
        return None
    return freqs[idx[0]]

def signed_to_q1_15(arr_signed):
    arr_q15 = np.round(arr_signed * (2**15 - 1)).astype(np.int16)
    return arr_q15 & 0xFFFF

def q1_15_to_signed(arr_q15):
    arr_signed = arr_q15.astype(np.int16)
    arr_float = arr_signed / (2**15 - 1)
    return arr_float
    
def writeTXT(arr, binDigit=16, filepath="output.txt", prefix=True, verbose=False):
    arr = np.array(arr)

    with open(filepath, 'w', encoding='utf-8') as f:
        for v in arr:
            if isinstance(v, float):
                val = int(np.round(v * (2**binDigit)))
            else:
                val = int(v)

            val &= (1 << binDigit) - 1

            if prefix:
                f.write(f"0x{val:0{binDigit//4}X}\n")
            else:
                f.write(f"{val:0{binDigit//4}X}\n")

    if (verbose):
        print(f"Saved {len(arr)} samples to {filepath}")

def readTXT(dir, binDigit, fracBits):
    arr = []
    with open(dir, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(('0x', '0X')):
                line = line[2:]
            val = int(line, binDigit)

            if (binDigit > 0) :
                if val >= (1 << (binDigit - 1)):
                    val -= (1 << binDigit)

                real_val = val / (2**fracBits)
                arr.append(real_val)
            else:
                arr.append(val)
    return np.array(arr)

def fft_filter(sample):
    n_fft = 4096

    # FFT
    freq_resp = np.fft.fft(sample, n_fft)

    # One-sided magnitude
    mag = np.abs(freq_resp[:n_fft//2])
    mag_db = 20 * np.log10(mag / np.max(mag))

    # Frequency axis (0 ~ 0.5 normalized)
    freq_axis = np.linspace(0, 0.5, n_fft//2, endpoint=False)

    return freq_axis, mag_db

def plot_filter_freq_domain(freqs, mag_db, cutoff_3dB=None, stop_start=None, ax=None):

    if ax is None:
        fig, ax = plt.subplots(figsize=(12, 4))
    else:
        fig = ax.figure

    ax.plot(freqs, mag_db, label="Magnitude", linewidth=1.0)

    # 3 dB cutoff
    if cutoff_3dB is not None:
        ax.axvline(cutoff_3dB, color="red", linestyle="--", label=f"3 dB cutoff ({cutoff_3dB:.4f})")

    # stopband start
    if stop_start is not None:
        ax.axvline(stop_start, color="purple", linestyle="--", label=f"Stopband Start ({stop_start:.4f})")

    ax.set_title("Frequency-Domain Impulse Response")
    ax.set_xlabel("Normalized Frequency")
    ax.set_ylabel("Magnitude [dB]")
    ax.set_ylim(-100, 5)
    ax.grid(True)
    ax.legend(loc="best")

    return fig, ax

def plot_filter_time_domain(coeff, ax=None):
    coeff_center_idx = len(coeff) // 2
    coeff_center_val = coeff[coeff_center_idx]
    
    coeff_last_idx = len(coeff) - 1
    coeff_last_val = coeff[coeff_last_idx]
    
    if ax is None:
        fig, ax = plt.subplots(figsize=(10,4))
    else:
        fig = ax.figure
        
    ax.stem(coeff, basefmt=" ", use_line_collection=True)

    ax.scatter(coeff_center_idx, coeff_center_val, color='red', zorder=5, label=f"Center ({coeff_center_idx}, {coeff_center_val:.4f})")
    ax.scatter(coeff_last_idx, coeff_last_val, color='purple', zorder=5, label=f"Last ({coeff_last_idx}, {coeff_last_val:.4f})")

    ax.set_title("Time-Domain Impulse Response")
    ax.set_xlabel("Tap Index")
    ax.set_ylabel("Amplitude")
    ax.legend(loc="upper right")
    ax.grid(True)
    
    return fig, ax
    
def FILTER_COEF_GEN(filter_type='lowpass', num_taps=101, folded=True,
                    cutoff=0.25, alpha=0.35, sps=8, span_symbols=6,
                    window='hamming', normalize=True, to_1Q15=True):

    # ---------------------------------------------
    # 1) Lowpass FIR
    # ---------------------------------------------
    if filter_type.lower() == 'lowpass':
        h = signal.firwin(num_taps, cutoff, window=window)

    # ---------------------------------------------
    # 2) Raised Root Cosine FIR
    # ---------------------------------------------
    elif filter_type.lower() in ('rrc', 'srrc'):
        num_taps = sps * span_symbols + 1
        t = np.arange(-span_symbols/2, span_symbols/2 + 1/sps, 1/sps)
        h = np.zeros_like(t)

        for i, ti in enumerate(t):
            if np.isclose(ti, 0.0):
                h[i] = 1.0 - alpha + (4*alpha/np.pi)
            elif np.isclose(abs(ti), 1/(4*alpha)):
                h[i] = (alpha/np.sqrt(2)) * (
                    ((1 + 2/np.pi) * np.sin(np.pi/(4*alpha))) +
                    ((1 - 2/np.pi) * np.cos(np.pi/(4*alpha)))
                )
            else:
                num = (np.sin(np.pi*ti*(1-alpha)) +
                       4*alpha*ti*np.cos(np.pi*ti*(1+alpha)))
                den = np.pi*ti*(1 - (4*alpha*ti)**2)
                h[i] = num / den

    else:
        raise ValueError("filter_type must be 'lowpass' or 'rrc'")
    if normalize:
        h /= np.sum(h)
    if to_1Q15:
        h = signed_to_q1_15(h)
    if folded:
        h = h[:(num_taps + 1)//2]
        print(f"Folded Filter Coefficient Generated, TAPS : {len(h)}")
    else:
        print(f"Filter Coefficient Generated, TAPS : {len(h)}")

    return h, num_taps

def getFullCoeff(folded):
    numTap = len(folded)
    
    if (numTap % 2 == 1):
        numTap = numTap + numTap - 1
        coeffs_full = np.concatenate((folded, folded[-2::-1]))  # Odd taps
    else:
        numTap = numTap + numTap
        coeffs_full = np.concatenate((folded, folded[::-1]))    # Even taps
        
    return coeffs_full, numTap
    
directory               = ""
filtDataFileName        = directory + "/FILT_DATA_IN.txt"
filtDataOutFileName     = directory + "/Symmetric_FIR_DATA_OUT.txt"

numBinDigit = 16 # Q1.15
L           = 8
span        = 8

# ===============================================================================================================
# Figure Setup
# ===============================================================================================================

fig, axs = plt.subplots(2, 2, figsize=(16, 12))

# ===============================================================================================================
# Python Reference Model
# ===============================================================================================================

h, numTap           =   FILTER_COEF_GEN('rrc', folded=True, alpha=0.35, sps=L, span_symbols=span, to_1Q15=True)
h_full, numTap      =   getFullCoeff(h)
h_float             =   q1_15_to_signed(h_full)

freq, mag           =   fft_filter(h_float)
cutoff_3dB          =   find_3dB_cutoff(freq, mag)
stop_start          =   find_stopband_start(freq, mag, threshold=-40)

plot_filter_time_domain(h_float, ax=axs[0, 0])
plot_filter_freq_domain(freq, mag, cutoff_3dB=cutoff_3dB, stop_start=stop_start, ax=axs[0, 1])

fig.text(0.02, 0.75, "Python Generated", rotation='vertical', ha='center', va='center', fontsize=14)

# ===============================================================================================================
# RTL Model
# ===============================================================================================================

rtl_h_float                     =   readTXT(filtDataOutFileName, numBinDigit, numBinDigit-1)
rtl_h_float                     =   [x for x in rtl_h_float if x != 0]

rtl_freq, rtl_mag               =   fft_filter(rtl_h_float)
rtl_cutoff_3dB                  =   find_3dB_cutoff(rtl_freq, rtl_mag)
rtl_stop_start                  =   find_stopband_start(rtl_freq, rtl_mag, threshold=-40)

plot_filter_time_domain(rtl_h_float, ax=axs[1, 0])
plot_filter_freq_domain(rtl_freq, rtl_mag, cutoff_3dB=rtl_cutoff_3dB, stop_start=rtl_stop_start, ax=axs[1, 1])

fig.text(0.02, 0.25, "RTL Generated (Except Zero)", rotation='vertical', ha='center', va='center', fontsize=14)

# ===============================================================================================================
# Figure Display
# ===============================================================================================================

plt.show()