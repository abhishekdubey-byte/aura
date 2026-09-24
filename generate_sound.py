import wave
import struct
import math

def generate_magical_sound(filename="assets/audio/reveal.wav"):
    sample_rate = 44100
    duration = 2.0  # seconds
    num_samples = int(sample_rate * duration)
    
    # Open WAV file for writing
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(2)  # Stereo
        wav_file.setsampwidth(2)  # 2 bytes per sample (16-bit)
        wav_file.setframerate(sample_rate)
        
        for i in range(num_samples):
            t = float(i) / sample_rate
            
            # Envelope (quick attack, long decay)
            envelope = math.exp(-3.0 * t)
            
            # Frequencies for a chord (C Major 7: C, E, G, B)
            freqs = [523.25, 659.25, 783.99, 987.77]
            
            sample_val = 0
            for freq in freqs:
                # Add some vibrato (frequency modulation)
                vibrato = math.sin(2.0 * math.pi * 6.0 * t) * 5.0
                actual_freq = freq + vibrato
                
                # Sine wave
                sample_val += math.sin(2.0 * math.pi * actual_freq * t)
                
                # Add a higher harmonic for shimmer
                sample_val += 0.3 * math.sin(2.0 * math.pi * (actual_freq * 2.0) * t)
            
            # Normalize and apply envelope
            sample_val = (sample_val / (len(freqs) * 1.3)) * envelope
            
            # Add a "sweep" or "shimmer" effect by modulating volume with a high frequency
            shimmer = 1.0 + 0.2 * math.sin(2.0 * math.pi * 15.0 * t)
            sample_val *= shimmer
            
            # Convert to 16-bit integer
            int_val = int(sample_val * 32767.0)
            
            # Ensure within bounds
            if int_val > 32767: int_val = 32767
            if int_val < -32768: int_val = -32768
                
            # Pack left and right channels
            data = struct.pack('<h', int_val) + struct.pack('<h', int_val)
            wav_file.writeframesraw(data)

if __name__ == "__main__":
    generate_magical_sound()
    print("Sound generated!")
