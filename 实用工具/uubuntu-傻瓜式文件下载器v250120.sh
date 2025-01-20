#!/bin/bash

##################################################################
#                                                                #
#                          a爱来自小尘                             #
#                  https://github.com/mcxiaochenn/My-Main        #
##################################################################

# 定义配置文件路径
config_file="./proxy.conf"

# 检查配置文件是否存在
if [ -f "$config_file" ]; then
    # 读取配置文件中的代理地址
    proxy_address=$(cat "$config_file")
    echo "发现现有代理配置：$proxy_address"
    echo "是否使用现有代理[y/n]?"
    read use_existing_proxy
else
    use_existing_proxy="n"  # 默认选择不使用现有代理
fi

# 弹出shell窗口，询问是否使用代理
echo "是否使用代理[y/n]:"
read use_proxy

# 如果使用代理并且没有配置文件，或者用户选择使用现有代理
if [ "$use_proxy" == "y" ] || [ "$use_existing_proxy" == "y" ]; then
    # 如果配置文件没有代理地址，询问用户输入代理地址
    if [ -z "$proxy_address" ]; then
        echo "请输入代理地址 (例如 0.0.0.0:10808):"
        read proxy_address
        # 保存代理地址到配置文件
        echo "$proxy_address" > "$config_file"
        echo "代理地址已保存到配置文件 $config_file"
    fi
    
    # 自动添加 http 或 https
    proxy_http="http://$proxy_address"
    proxy_https="https://$proxy_address"

    export http_proxy=$proxy_http
    export https_proxy=$proxy_https

    echo "代理已设置为 $proxy_http 和 $proxy_https"
fi

# 询问下载方式
echo "下载方式 [wget/axel]:"
read download_method

# 询问下载链接
echo "下载链接:"
read download_link

# 询问下载路径（默认路径为当前目录）
echo "请输入下载路径 (默认: ./):"
read download_path
download_path=${download_path:-"./"}  # 如果用户没有输入，则默认为当前目录

# 如果是axel，设置更多选项
if [ "$download_method" == "axel" ]; then
    echo "请输入axel下载时的并发数（默认为32）:"
    read axel_threads
    axel_threads=${axel_threads:-32}  # 如果用户没有输入则默认为32
    download_command="axel -n $axel_threads $download_link -o $download_path"
elif [ "$download_method" == "wget" ]; then
    download_command="wget -P $download_path $download_link"
else
    echo "无效的下载方式，默认使用wget"
    download_command="wget -P $download_path $download_link"
fi

# 创建一个新的终端并执行下载命令
echo "开始下载..."
if command -v gnome-terminal &> /dev/null; then
    gnome-terminal -- bash -c "$download_command; exec bash"  # 使用 gnome-terminal
elif command -v xterm &> /dev/null; then
    xterm -e "bash -c '$download_command; exec bash'"  # 使用 xterm
else
    echo "没有找到支持的终端程序（gnome-terminal 或 xterm）。"
    echo "直接在当前终端执行命令：$download_command"
    bash -c "$download_command"  # 如果没有终端模拟器，直接在当前终端执行
fi

echo "新的终端窗口已启动，下载将在其中继续进行。"
