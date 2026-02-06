# Slow Bongo

A bongo cat that sits in your bar and slaps when you type. When i write QML i feel like im programming with my toes, this shit is not pretty.

## Features

- **Keyboard Reactive**: Cat taps its paws in alternation when you type
- **Audio Reactive**: Optional rave mode and tappy mode that react to music
- **Customizable Appearance**: Choose from multiple color schemes and adjust size
- **Font-Based Animation**: Uses a bongo cat font for easy rendering
- **Auto-Detection**: Automatically detects keyboard input devices
- **Bar Widget**: Compact widget that fits seamlessly in your Noctalia bar

## Configuration

The plugin offers several customization options available in the settings panel:

### Input Devices

The plugin automatically detects keyboard input devices on first run. You can manually select which input devices to monitor from the settings panel.

### Colors

Choose from four color schemes:
- **Default**: Uses the default on-surface color
- **Primary**: Uses your theme's primary color
- **Secondary**: Uses your theme's secondary color
- **Tertiary**: Uses your theme's tertiary color

### Rave Mode

When enabled, the cat changes colors to the beat when music is playing. Requires `cava` to be installed.

### Tappy Mode

When enabled, the cat taps along to the beat when music is playing instead of only reacting to keyboard input. Requires `cava` to be installed.

### Size and Position

- **Cat Size**: Scale the cat from 50% to 150% of default size
- **Font Weight**: Adjust the cat's line thickness from Thin to Black
- **Vertical Position**: Fine-tune the cat's vertical alignment in the bar

## Requirements

### Essential

- **evtest**: Required for keyboard input detection
  ```bash
  # Fedora/RHEL
  sudo dnf install evtest

  # Ubuntu/Debian
  sudo apt install evtest

  # Arch
  sudo pacman -S evtest
  ```

- **Input group membership**: Your user must be in the `input` group to read keyboard events
  ```bash
  sudo usermod -a -G input $USER
  ```
  Restart for the group change to take effect.

### Optional

- **cava**: Required for rave mode and tappy mode audio reactivity
  ```bash
  # Fedora/RHEL
  sudo dnf install cava

  # Ubuntu/Debian
  sudo apt install cava

  # Arch
  sudo pacman -S cava
  ```

## Troubleshooting

### Cat not responding to keyboard input

1. Check that `evtest` is installed:
   ```bash
   which evtest
   ```

2. Verify you're in the `input` group:
   ```bash
   id -nG | grep input
   ```

3. Make sure at least one input device is selected in the settings panel.

### Rave mode or tappy mode not working

Ensure `cava` is installed and the CavaService is running in your Noctalia shell:
```bash
which cava
```

## Technical Details

- Uses `evtest` to monitor keyboard events from `/dev/input/event*` devices
- Integrates with Noctalia's CavaService for audio visualization
- Custom font file (`bongocatfont.woff`) contains the cat animations
- Alternates between left (1) and right (2) paw animations, returning to idle (0) after configurable timeout

## License

MIT

## Credits

- Thank you to [Kitgore](https://github.com/kitgore) for the amazing bongo cat font 
- Noctalia plugins for the amazing guides/examples
