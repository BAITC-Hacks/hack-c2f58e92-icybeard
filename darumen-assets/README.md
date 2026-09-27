# Darumen logo assets
Colours (с 28.09.2026, Палитра C «Белый холст»): знак — блок Ink #333333, дуга и сектор Violet #5B5BD6; иконки на белом #FFFFFF; холст #F5F6F8. Прежние Navy/Sky и Navy/Coral сняты.

## Web — paste into <head>
```html
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon-32.png" sizes="32x32">
<link rel="apple-touch-icon" href="/apple-touch-icon-180.png">
<link rel="manifest" href="/site.webmanifest">
<meta name="theme-color" content="#5B5BD6">
```
- svg/logo-animated.svg — looping loader/splash, pure CSS, stops under prefers-reduced-motion. Use via <img> or inline.
- svg/lockup*.svg use live text (Golos Text via Google Fonts). Outline the text in Figma/Illustrator before production use.

## iOS
ios/icon-1024.png goes to App Store; the rest fill AppIcon.appiconset. Square, full-bleed — iOS rounds corners. ≤40px sizes use the simplified solid-half mark.

## Android
mipmap-*/ic_launcher(.png|_round.png) for legacy; adaptive-foreground/background-432 for API 26+ (foreground mark sits inside the 66dp safe zone). play-store-512.png for Google Play.
