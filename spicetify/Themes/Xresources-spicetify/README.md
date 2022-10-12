# Xresources

A [Spicetify](https://github.com/khanhas/spicetify-cli) theme which follow Xresources colors. This is primarily a personal use since the original author's pull request got rejected(?) and it seems to be abandoned. I had trouble finding an "easy" mechanism for spicetify theming that worked.

I primarily copy the my wal settings via a startup mechanism (in my case, my bspwm script):

```
cp ~/.cache/wal/colors.Xresources ~/.Xresources &
```

## Screenshots

### wallpaper example
<img src="https://github.com/brickfrog/Xresources-spicetify/blob/master/screenshots/wallpaper.jpg" width=50% height=50%>

## highlights from pywal
<img src="https://github.com/brickfrog/Xresources-spicetify/blob/master/screenshots/example.png" width=50% height=50%>


Follow colors definitions from Xresources + an accent color.

> Colors definitions are exclusively based on Xresources colors. This mean no color_scheme definition is necessary in spicetify config. Either light or dark, the theme should follow nicely your defined color scheme with Xresources (see examples).
>
> You just need to adjust the `accent` color in `color.ini`.

>Even if not necessary, there are a `dark` and `light` color scheme definition which only serve the purpose as fallback values in case no colors are retrieved from Xresources. Obviously, this seems quite pointless as if you want to use this theme, you have Xresources colors defined!  

## Enable
to use it :
```bash
spicetify config current_theme Xresources-spicetify
spicetify apply
```

Original Author : [devcroc](https://github.com/devcroc)
