# Plinth

[English](README.md) · 简体中文

一条住在 Mac 桌面上的小木鱼。点它一下，笃的一声，仅此而已，敲了也不积功德。

![Plinth 自带的十二款皮肤，各自立在底座上，木槌悬在上方：木鱼、卡通鱼、水墨鱼、玉鱼、像素鱼、朱漆、铜磬、空格键、竹节、苔石、活塞、CRT 终端](docs/skins.png)

寺院诵经时用木鱼打拍子。至于为什么刻成鱼的样子，《敕修百丈清规》里有一句：「鱼昼夜常醒，刻木象形击之，所以警昏惰也。」Plinth 把这样一条木鱼放在小小的霓虹底座上，摆在你的窗口旁边。

很多电子木鱼每敲一下就飘出一个「功德 +1」，还一直替你记着总数。Plinth 不这样做。梁武帝问达摩：「造寺写经度僧，有何功德？」达摩说：「并无功德。」你敲下第一声，得到的也是这个回答，之后也不会有任何计数。

## 功能

- **敲它。** 点一下木鱼，木槌落下，木头微微一沉，发出一声。敲之前静得越久，余音越长。
- **自动敲击。** 让它按固定的节奏自己敲，每隔 0.5 到 4 秒一下。也可以设成敲满 108 下就停，正好念珠一圈。
- **打字时跟着敲。** 可选。在任何 App 里每按一个键，就敲一下，打字停下来想一想，再按下的那个键会响得更长。不需要任何特殊权限：Plinth 只知道键什么时候按下，不知道按的是哪个键。
- **几句话。** 木鱼有几句话要说，每句只说一次。
- **不碍事。** 不占程序坞。可以浮在窗口上方，也可以沉到桌面上，拖到哪儿都行。
- **皮肤。** 自带十二款：木鱼、玉鱼、朱漆、铜磬、像素鱼、卡通鱼、水墨鱼、空格键、竹节、苔石、活塞、CRT 终端，每款都有自己的木槌和敲击声，大多还有自己的敲击效果。空格键被敲时会按下再回弹，不会真的输入字符；活塞压下再复位，CRT 短暂亮起波形，不执行命令。也可以换成别的：一个放着几帧图片的文件夹，或者单独一张图片。

木鱼说的几句话都用原文。菜单和设置跟随系统语言，系统是简体中文时显示中文，其他情况显示英文。

右键点木鱼，或者点菜单栏上的图标，能看到所有选项。菜单栏图标和桌面上的木鱼用的是同一款皮肤。

## 下载

从 [Releases](https://github.com/rubycatco/plinth/releases) 下载 `Plinth-x.y.z.dmg`，打开后把 Plinth 拖进「应用程序」文件夹。需要 macOS 14 Sonoma 或更新版本。也可以按下面的步骤自己构建。

## 系统要求

- macOS 14 Sonoma 或更新版本
- 从源码构建需要 Xcode 15 或更新版本

## 构建

```sh
git clone https://github.com/rubycatco/plinth.git
cd plinth
./scripts/build_app.sh
open build/Plinth.app
```

脚本会构建同时支持 Apple 芯片和 Intel 的通用二进制，组装出 `build/Plinth.app`，并做 ad hoc 签名。想一直用的话，把它拖进 `/Applications`。`./scripts/make_dmg.sh` 会把它打包成磁盘映像，签名、公证和发布的做法见 [docs/RELEASING.md](docs/RELEASING.md)（英文）。

开发时也可以直接 `swift run`，但离开 App 包，木鱼找不到自己的图片，要看完整效果还是用脚本。

## 皮肤

Plinth 从这里读取皮肤：

```
~/Library/Application Support/Plinth/Skins/
```

可以从菜单 **皮肤 → 打开皮肤文件夹** 打开它，或者用 **皮肤 → 添加皮肤…** 添加。App 运行时，这里的改动会自动生效。

皮肤可以是一张图片（PNG、JPEG 等），也可以是这样一个文件夹：

```
my-skin/
├── idle.png    静止时的样子（必需）
├── blink.png   每隔几秒眨一下眼时显示（可选）
├── hit.png     木槌落下后立刻显示（可选）
├── mallet.png  这款皮肤自己的木槌（可选）
├── impact.png  这款皮肤自己的敲击效果（可选）
└── skin.json   名字、木槌落在哪里，以及敲击声（可选）
```

眨眼和被敲中也可以是一小段序列：`blink-1.png`、`blink-2.png`……眨眼会一路播到最后一帧（闭眼）再播回来；被敲中会播到最后一帧，停一下，再回到静止。帧与帧之间按屏幕刷新率交叉淡入淡出，所以两三帧也能动得很顺。

每帧应是透明背景的正方形，512 × 512 就很好。皮肤自己的 `mallet.png` 会替换共用的 [`mallet.png`](App/Resources/mallet.png)，摆法也要一样：水平放，槌头在左，握柄在最右边。`impact.png` 会替换共用的霓虹敲击效果，按原样绘制，所以可以是深色的，比如一团墨。`skin.json` 给出槌头的落点，用画面宽和高的比例表示，从左上角算起，以及这款皮肤用哪种敲击声。敲击声是合成的，不是录音：

```json
{ "name": "我的皮肤", "strike": [0.6, 0.3], "voice": "jade" }
```

`voice` 可以是 `wood`、`lacquer`、`ink`、`cartoon`、`pixel`、`jade`、`bowl`、`key`、`bamboo`、`stone`、`piston`、`crt`。不写就是木鱼。没有被敲中画面的皮肤，会在木槌落下时微微一沉。内置皮肤在 [`App/Resources/Skins`](App/Resources/Skins)。几条鱼都没有眨眼和被敲中的画面，这是有意的：鱼昼夜常醒，被敲的时候也不闭眼。

## 语言

界面文字在 [`App/Resources/zh-Hans.lproj`](App/Resources/zh-Hans.lproj)：`Localizable.strings` 是菜单和设置，`Skins.strings` 是内置皮肤的名字。想加一种语言，把这个文件夹复制成 `<语言代码>.lproj`，翻译里面的值，再把语言代码加进 [`App/Info.plist`](App/Info.plist) 的 `CFBundleLocalizations`。

## 项目结构

```
Sources/Plinth/     SwiftUI + AppKit 源码
App/                Info.plist、App 图标和打包进 App 的资源
scripts/            构建和打包磁盘映像的脚本
docs/               签名与发布说明（英文），以及 README 用的图
.github/workflows/  发布流程
tools/              绘制皮肤敲击效果的脚本（Python：NumPy、Pillow）
```

## 许可

代码采用 [MIT](LICENSE) 许可，美术采用 CC0。敲击声由程序合成，详见 [CREDITS.md](CREDITS.md)（英文）。
