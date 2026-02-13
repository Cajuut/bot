from PIL import Image, ImageDraw

def create_icon():
    size = 1024
    # Discord Blurple: #5865F2 (88, 101, 242)
    bg_color = (88, 101, 242)
    white = (255, 255, 255)
    
    img = Image.new('RGB', (size, size), bg_color)
    draw = ImageDraw.Draw(img)
    
    # Simple Robot Head Shape (Minimalist)
    # Head rect
    margin = 200
    head_left = margin
    head_top = margin + 100
    head_right = size - margin
    head_bottom = size - margin
    
    # Rounded rectangle for head
    radius = 100
    draw.rounded_rectangle([head_left, head_top, head_right, head_bottom], radius=radius, fill=white)
    
    # Eyes
    eye_size = 80
    eye_y = head_top + 250
    draw.ellipse([head_left + 150, eye_y, head_left + 150 + eye_size, eye_y + eye_size], fill=bg_color)
    draw.ellipse([head_right - 150 - eye_size, eye_y, head_right - 150, eye_y + eye_size], fill=bg_color)
    
    # Antenna
    antenna_w = 40
    antenna_h = 150
    draw.rectangle([(size // 2) - (antenna_w // 2), head_top - antenna_h, (size // 2) + (antenna_w // 2), head_top], fill=white)
    # Antenna tip
    tip_size = 60
    draw.ellipse([(size // 2) - (tip_size // 2), head_top - antenna_h - (tip_size // 2), (size // 2) + (tip_size // 2), head_top - antenna_h + (tip_size // 2)], fill=white)

    import os
    os.makedirs('assets', exist_ok=True)
    img.save('assets/app_icon.png')
    print("Icon saved to assets/app_icon.png")

if __name__ == '__main__':
    create_icon()
