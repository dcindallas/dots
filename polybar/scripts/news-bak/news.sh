#!/bin/sh
#
# title: Polybar Module - News
# project-home: https://github.com/nivit/polybar-module-news
# license: MIT

# default values

quiet_mode="no"  # no output if there are no news

show_site="yes"  # display the name of source

show_date="yes"  # display the date of the news/podcast, if available
date_as_prefix="yes"  # otherwise as suffix if show_date="yes"
date_format="%d %b. %R -"  # see manpage strftime(3) for more conversion specifications

show_prefix="yes"
# RSS icon, code U+F09E, requires a switable font such as Awesome Font
news_prefix=""

use_colors="yes"
# a list of colors, separated by spaces, for the headlines
# see https://colorhunt.co/palettes or https://colorswall.com/ for some hint
colors="#28FFBF #FFEF76 #49FF00"
error_bg_color="#F44336"
error_fg_color="#FFFFFF"
warning_bg_color="#FFC107"
warning_fg_color="#212121"

reverse_order="yes"  # display news in the reverse order

show_menu="yes"  # show a menu with all news (via rofi, right click)
menu_lines=20

# Use a link to a multimedial file if available
media_link="yes"
audio_player="gmplayer"
# https://github.com/mpv-player/mpv/blob/master/TOOLS/umpv
# video_player="umpv"
video_player="mpv"
# the icons require a suitable font such as Font Awesome
audio_prefix=" (audio)"
video_prefix=" (video)"

search_prompt="Search"

# max number of news to show per feed, 0 (i.e. all news) or a whole number
max_news=0

length=0  # number of characters for the output to the bar; zero means no limit
use_ellipsis="yes"  # yes|no; used only when length > 0

open_cmd="xdg-open"
breaking_news="no"

python_cmd=python3

# start script
readonly _menu_lines=15
readonly module_dir=${HOME}/.config/polybar/scripts/news
readonly conf_dir=${module_dir}/conf
readonly datadir=${module_dir}/data
readonly all_news=${datadir}/all_news
readonly checksum_file="${datadir}/feed_list.md5"
readonly download_script=${module_dir}/download_feeds.py
readonly file_lock=${datadir}/.file_lock
readonly hash_salt="https://github.com/nivit/polybar-module-news"
readonly news_conf=${conf_dir}/news.conf
readonly news_url=${datadir}/news.url
readonly status_file=${datadir}/status
readonly status_colors=${datadir}/status_colors
os_name="$(uname -s)"
readonly os_name
readonly select_message='
- Press <b>Shift + Enter</b> to select a feed
- Press <b>Enter</b> to accept the selection
- Press <b>Esc</b> to cancel
- Press <b>Control + Enter</b> to deselect all feeds

  <b>Current feeds are highlighted (if the rofi theme is configured to do it)</b>.
  <b>They must be selected again if necessary</b>.
'

# files with a list of URLs to fetch
feeds_list="${conf_dir}/feeds_list"
feeds_list_breaking_news="${conf_dir}/feeds_list_breaking_news"

grep_cmd=/bin/grep
md5_cmd=/usr/bin/md5sum
menu_scrollbar=true
rofi_case=""  # case is sensitive
rofi_config=${conf_dir}/config.rasi
rofi_options=""
rofi_width=""  # "auto" or "" (menu width)
update_status="no"


print_msg() {

    if [ "${use_colors}" = "yes" ]; then
        if [ "${1}" = "warning" ]; then
            bg_color="${warning_bg_color}"
            fg_color="${warning_fg_color}"
        else
            bg_color="${error_bg_color}"
            fg_color="${error_fg_color}"
        fi
        /usr/bin/printf "%s" "%{B${bg_color} F${fg_color}} -- ${2} -- %{B- F-}"
    else
        /usr/bin/printf "-- %s --" "${2}"
    fi

    if [ "${1}" = "error" ]; then
        exit 0  # actually ignore the error...
    fi
}


lines_number() {
    # return the number of lines in a file
    if [ -f "${1}" ]; then
        awk 'END {print NR}' < "$1"
    fi
}

add_date() {
    if [ "${seconds}" != "0" ]; then
        if [ "${os_name}" = "Linux" ]; then
            news_date="$(/bin/date -d @"${seconds}" +"${date_format}")"
        else
            news_date="$(/bin/date -jf %s "${seconds}" +"${date_format}")"
        fi

        if [ "${date_as_prefix}" = "yes" ]; then
            news_title="${news_date} ${news_title}"
        else
            news_title="${news_title} ${news_date}"
        fi
    fi
}

add_prefix() {
    # add a prefix to the news title

    if [ "${media_link}" = "yes" ]; then
        case "${media_type}" in
            audio/*)
                prefix="${audio_prefix}"
                ;;
            video/*)
                prefix="${video_prefix}"
                ;;
            *)
                prefix="${news_prefix}";;
        esac
    fi
    news_title="${prefix} ${feed_title}${news_title}"
}

add_ellipsis() {
    # add ... to the truncated title, if necessary

    if [ "${length}" -gt 0 ] && \
        [ "${length}" -lt "${#news_title}" ]; then
        if [ "${use_ellipsis}" = "yes" ] ; then
            ellipsis="..."
            length="$(( length - 3 ))"
        else
            ellipsis=""
        fi
        news_title="$(/usr/bin/printf "%s" "${news_title}" | cut -c -"${length}")"
        news_title="${news_title% *}${ellipsis}"
    fi
}

get_md5_checksum() {

    _s="${1}"

    if [ "${os_name}" = "FreeBSD" ] || \
        [ "${os_name}" = "OpenBSD" ] || \
        [ "${os_name}" = "NetBSD" ]; then
            /sbin/md5 -q -s "${_s}"
    else
        # Linux dive is a reverse 4½ somersault in the pike position rated at 4.8 (LOL)
        echo "${_s}" | /usr/bin/md5sum | cut -d ' ' -f 1
    fi
}

parse_news_line() {
    # parse a line of a news file (datadir/_*)
    IFS="$(/usr/bin/printf "\t")"
    # shellcheck disable=SC2068

    set -- $@
    media_type="${1}"
    seconds="${2}"
    url="${3}"
    news_title="${4}"

    if [ "${media_link}" = "yes" ]; then
        case "${media_type}" in
            audio/*)
                open_cmd="${audio_player}"
                ;;
            video/*)
                open_cmd="${video_player}"
                ;;
            *)
                open_cmd="xdg-open";;
        esac
    fi

    if [ "${show_date}" = "yes" ]; then
        add_date
    fi

    if [ "${show_prefix}" = "yes" ]; then
        add_prefix
    fi

    add_ellipsis
}


parse_status_line() {
    # parse a line of the status file (datadir/status)
    IFS="$(/usr/bin/printf "\t")"

    # shellcheck disable=SC2068
    set -- $@
    news_index="${1}"
    available_news="${2}"
    #active="${3}"
    breaking_news="${4}"

    filename="${datadir}/${5}"
    if [ "${use_colors}" = "yes" ]; then
        color="${6}"
    else
        color=""
    fi

    if [ "${show_site}" = "yes" ]; then
        feed_title="${7} - "
    else
        feed_title=""
    fi

    #max_news_length="${8}"
    #feed_url="${9}"
    #etag="${10}"
    #modified="${11}"
}


setup_rofi() {

    if [ -f "${rofi_config}" ]; then
        menu_width="$(get_rofi_value width)"

        if [ -z "${menu_width}" ] || [ "${menu_width#-}" != "${menu_width}" ] && \
            [ "${rofi_width}" = "auto" ]; then
            news_len="$(awk '
                NR % 2 == 1 {
                    if (max < length()) {
                        max = length()
                    }
                }
                # return a negative value to indicate a character width
                # see rofi(1)
                END {
                    print -max - 2
                }
            ' "${all_news}")"
            menu_width="${news_len}"
        fi
    fi

    # check if menu_lines is a number, if not get the value from rofi conf.
    if [ -n "$(echo "${menu_lines}" | tr -d "0-9")" ]; then
        menu_lines="$(get_rofi_value lines)"
    fi

    if [ -z "${menu_lines}" ]; then
        menu_lines=${_menu_lines}
    fi

}


search() {
    active_feeds="$(awk '
        BEGIN {IFS="\t"}
        { if ($2 != "0" && $3 == "1") {print $0}}' \
        "${status_file}")"

    setup_rofi

    if [ "${reverse_order}" = "yes" ]; then
        reverse_order="-r"
    else
        reverse_order=""
    fi

    news_number="$(echo "${active_feeds}" | cut -f 2 | \
        awk '{total=total+$0} END {print total}')"

    if [ "${news_number}" -lt "${menu_lines}" ]; then
        menu_lines="${news_number}"
        menu_scrollbar="false"
    fi

    choice="$(echo "${active_feeds}" | \
    while read -r status_line; do
        parse_status_line "${status_line}"
        # shellcheck disable=SC2086
        sort -k 2 ${reverse_order} "${filename}" | \
        while read -r news_line; do
            parse_news_line "${news_line}"
            echo "${news_title}"
        done
    done | rofi \
        -config "${rofi_config}" \
        "${rofi_options}" \
        -p "${search_prompt}" \
        -dmenu \
        -format d \
        -lines "${menu_lines}" \
        "${rofi_case}" \
        -theme-str "listview{scrollbar:${menu_scrollbar};}" \
        -width "${menu_width}")"

    if [ -n "${choice}" ]; then
        range=0
        echo "${active_feeds}" | \
        while read -r status_line; do
            parse_status_line "${status_line}"
            if [ "$(( choice <= ( range + available_news ) ))" = "1" ]; then
                index="$(( choice - range ))"
                news_line="$(sort -k2 "${reverse_order}" "${filename}" | \
                    sed -n -e "${index}p")"
                parse_news_line "${news_line}"
                exec ${open_cmd} "${url}"
            fi
            range="$((range + available_news))"
        done;
    fi
}


download_feeds() {

    if [ -f "${file_lock}" ]; then
        exit 0
    fi

    if [ -n "${1}" ]; then
        _last_minutes="${1}";
    else
        _last_minutes=0
    fi

    if command -v "${python_cmd}" > /dev/null 2>&1; then
        if ! ${python_cmd} -c 'import feedparser' > /dev/null 2>&1; then
            print_msg error "install python module feedparser, please!"
        fi
    else
        print_msg error "install/configure a python 3 interpreter, please!"
    fi

    if [ "${media_link}" = "yes" ]; then
        media_link="--media-link"
    else
        media_link=""
    fi

    if [ "${use_colors}" = "yes" ] && \
        [ "${colors}" != "" ]; then
        colors_option="-c $(/usr/bin/printf "%s" "${colors}" | tr -d '[:blank:]')"
    else
        colors_option=""
    fi

    # check that max_news is a number: if not, set to 0 (all news)
    if [ -n "$(echo "${max_news}" | tr -d "0-9")" ]; then
        max_news=0
    fi

    (
        /usr/bin/touch "${file_lock}"

        # shellcheck disable=SC2086,SC2046
        "${python_cmd}" "${download_script}" -n "${max_news}" \
            ${colors_option} ${media_link} -l "${_last_minutes}" -- "${datadir}"

        rm -f "${file_lock}"
    )
}


change_colors() {
    # change the colors used for the headlines in the status file
    new_status_file=$(mktemp)

    # extract valid colors #[0-9a-fA-F]{6}
    colors="$(echo "${colors}" | ${grep_cmd} -o -E -e '#[0-9a-fA-F]{6}')"

    if [ -n "${colors}" ]; then
        colors_len="$(echo "${colors}" | awk 'END {print NR}')"
        counter=0

        IFS="$(/usr/bin/printf "\n")"
        while read -r status_line; do
            i="$(( (counter % colors_len) + 1 ))"

            new_color="$(echo "${colors}" | awk -v i="${i}" 'NR == i {print $1}')"
            current_color="$(echo "${status_line}" | cut -f 6)"
            echo "${status_line}" | sed -e "s,${current_color},${new_color},1"

            counter="$(( counter + 1 ))"
        done < "${status_file}" > "${new_status_file}"

        if [ -f "${file_lock}" ]; then
            print_msg warning "Downloading news/podcasts feeds"
            exit 0
        else
            /usr/bin/touch "${file_lock}"
            mv -f "${new_status_file}" "${status_file}"
            rm -f "${file_lock}"
        fi

        /usr/bin/printf "%s" "${md5_colors}" > "${status_colors}"
    fi
}

get_rofi_value() {
    # get a value from the rofi configuration.
    value="$(awk -F: -v search="$1" '
        BEGIN {
            regex=sprintf("^[[:space:]]*%s:", search);
        }
        $0 ~ regex {
            gsub(/;|[ \t]+/, "", $2);
            printf "%s", $2;
            exit 0
        }
    ' "${rofi_config}")"

    /usr/bin/printf "%s" "${value}"
}


# shellcheck disable=SC2120
check_feeds() {

    if [ -f "${file_lock}" ]; then
        print_msg warning "Downloading news/podcasts feeds"
        exit 0
    fi

    feeds_list_checksum="$(cat "${feeds_list}" "${feeds_list_breaking_news}" | "${md5_cmd}")"

    if [ ! -f "${checksum_file}" ] || [ ! -s "${checksum_file}" ]; then
        printf "%s" "${feeds_list_checksum}" > "${checksum_file}"
        return
    fi

    if [ "$(cat "${checksum_file}")" = "${feeds_list_checksum}" ]; then
        return
    else
        printf "%s" "${feeds_list_checksum}" > "${checksum_file}"
    fi

    new_status=$(mktemp)

    if [ "${breaking_news}" = "yes" ]; then
        update_feeds "${new_status}" "${feeds_list_breaking_news}" 1
    fi

    update_feeds "${new_status}" "${feeds_list}" 0

    (/usr/bin/touch "${file_lock}"
    mv -f "${new_status}" "${status_file}"
    rm -f "${file_lock}")
}


update_feeds() {
    _new_status="${1}"
    _feeds_list="${2}"
    _breaking_news="${3}"

    ${grep_cmd} -v '^$' "${_feeds_list}" | \
    while IFS= read -r url; do
        if [ "${_breaking_news}" = "0" ]; then
            _hash_salt=""
            _BN=""
        else
            _hash_salt="${hash_salt}"
            _BN="[BN]"
        fi
        url_hash="_$(get_md5_checksum "${url}${_hash_salt}")"
        n_line="$(${grep_cmd} -n "${url_hash}" "${status_file}")"
        n="$(echo "${n_line}" | cut -d : -f 1)"

        if [ -n "${n}" ]; then
            line="$(echo "${n_line}" | cut -d : -f 2-)"
            _title="$(echo "${line}" | cut -f 7)"
            if [ -n "${_title}" ]; then
                printf "%s" "${line}" | \
                    awk -v n="${max_news}" '
                        BEGIN {FS="\t";OFS="\t"}
                        {if (n < $2 && $3 == 1) {$1 = n}; print $0}' \
                        >> "${_new_status}"
            fi
        else
            /usr/bin/printf "0\t0\t1\t%s\t%s\t\t%s %s[NEW FEED]\t\t%s\t\t\t\n" \
                "${_breaking_news}"  "${url_hash}" "${url}" "${_BN}" "${url}" \
                >> "${_new_status}"
        fi
    done
}


select_feeds() {
    # function to select what feeds to show in the bar

    setup_rofi

    if [ -f "${feeds_list}" ] || [ -f "${feeds_list_breaking_news}" ]  && \
            [ -f "${status_file}" ]; then

        tmp_list="$(mktemp)"
        cut  -f 7 < "${status_file}" > "${tmp_list}"
        # shellcheck disable=SC2086
        old_feeds_numbers="$(awk '
            BEGIN {ORS=","}
            $3 ~ 1 {print NR - 1}
        ' "${status_file}" | sed -e 's,\,$,,1')"

        feeds_number="$(lines_number "${feeds_list}")"
        feeds_number="$(( feeds_number + $(lines_number "${feeds_list_breaking_news}") ))"

        if [ "${feeds_number}" -lt "${menu_lines}" ]; then
            menu_lines="${feeds_number}"
            menu_scrollbar="false"
        fi

        feeds_numbers="$(rofi \
            -config "${rofi_config}" \
            "${rofi_options}" -dmenu \
            -a "${old_feeds_numbers}" \
            "${rofi_case}" \
            -p "${search_prompt}" \
            -multi-select \
            -lines "${menu_lines}" \
            -format d \
            -theme-str "listview{scrollbar:${menu_scrollbar};}" \
            -mesg "${select_message}" < "${tmp_list}")"

        rm -f "${tmp_list}"

        # user pressed ESC
        if [ "${feeds_numbers}" = "" ]; then
            exit 0
        fi

        # user deselected all feeds
        if [ "${feeds_numbers}" = "-1" ] || 
                [ "${feeds_numbers}" = "0" ]; then
            new_status=$(mktemp)
            awk 'BEGIN {FS="\t"; OFS="\t"} {$1=0; $3=0; print $0}' \
            "${status_file}" > "${new_status}"
            (/usr/bin/touch "${file_lock}";
            cp -f "${new_status}" "${status_file}"
            rm -f "${file_lock}"
            rm -f "${new_status}"*)
            exit 0
        fi

        temp_file=$(mktemp)
        echo "${feeds_numbers}" | \
        while IFS= read -r feed_number; do
            url="$(cat "${feeds_list_breaking_news}" "${feeds_list}" | \
                sed -n -e "${feed_number}p")"
            url_hash="_$(get_md5_checksum "${url}")"
            if [ ! -f "${datadir}/${url_hash}" ]; then
                echo "yes" > "${temp_file}"
                break
            fi
        done

        # disable all feeds in the new status file
        new_status=$(mktemp)
        awk 'BEGIN {FS="\t"; OFS="\t"} {$1=0; $3=0; print $0}' \
            "${status_file}" > "${new_status}"
        # activate only the choosen feeds
        echo "${feeds_numbers}" | \
        while IFS= read -r ln; do
            sed -E -i.bak "${ln}s/^([0-9]+)\t([0-9]+)\t[01]/\2\t\2\t1/1" \
                "${new_status}"
        done

        (/usr/bin/touch "${file_lock}";
        cp -f "${new_status}" "${status_file}"
        rm -f "${file_lock}"
        rm -f "${new_status}"*)

        read -r update_status < "${temp_file}"
        if [ "${update_status}" = "yes" ]; then
            download_feeds
        fi
        rm -f "${temp_file}"
    fi

    exit 0
}


init_status_file() {

    if [ -f "${status_file}" ]; then
        rm -f "${status_file}"
        rm -f "${datadir}/_*"
    fi

    if [ -f "${feeds_list_breaking_news}" ] &&
        [ "${breaking_news}" = "yes" ]; then
        while IFS= read -r url; do
            url_hash="_$(get_md5_checksum "${url}${hash_salt}")"
            /usr/bin/printf "0\t0\t1\t1\t%s\t\t\t\t%s\t\t\n" \
                "${url_hash}" "${url}" >> "${status_file}"
        done < "${feeds_list_breaking_news}"
    fi

    if [ -f "${feeds_list}" ]; then
        while IFS= read -r url; do
            url_hash="_$(get_md5_checksum "${url}")"
            /usr/bin/printf "0\t0\t1\t0\t%s\t\t\t\t%s\t\t\n" \
                "${url_hash}" "${url}" >> "${status_file}"
        done < "${feeds_list}"
    fi
}


setup() {

    # override default values
    if [ -f "${news_conf}" ]; then
        # shellcheck source=news.conf disable=SC1091
        . "${news_conf}"
    fi

    if [ ! -d "${datadir}" ]; then
        mkdir -p "${datadir}"
    fi

    if [ ! -s "${status_file}" ] ||
            [ ! -f "${status_file}" ]; then
        init_status_file
        news_number="$(cut -f 2-4 "${status_file}" | \
            awk '{if ($2 == 1 && $3 == 0) {total=total+$1}} END {print total}')"
        if [ -z "${news_number}" ]; then
            if [ "${quiet_mode}" != "yes" ]; then
                echo "-- No news or no (regular) feeds selected --"
            fi
        else
            print_msg warning "Downloading news/podcasts feeds"
            download_feeds 1
            download_feeds 0
        fi
        exit 0
    fi

    if [ ! -f "${feeds_list}" ]; then
        print_msg error "no feeds file found!"
        exit 0
    fi

    if [ ! -f "${feeds_list_breaking_news}" ]; then
        /usr/bin/touch "${feeds_list_breaking_news}"
    fi

    if [ "${show_menu}" = "yes" ]; then
        if ! command -v rofi > /dev/null 2>&1; then
            print_msg error "install rofi program, please!"
        fi
    fi

    if ! command -v "${open_cmd}" > /dev/null 2>&1; then
        print_msg error "install ${open_cmd} program, please!"
    fi

    if [ ! -f "${rofi_config}" ]; then
        rofi_config=""
    fi

    menu_case="$(get_rofi_value case-sensitive)"
    if [ "${menu_case}" = "false" ]; then
        rofi_case="-i"
    fi

    if [ "${os_name}" = "FreeBSD" ] || \
        [ "${os_name}" = "OpenBSD" ] || \
        [ "${os_name}" = "NetBSD" ]; then
        grep_cmd="/usr/bin/grep"
        md5_cmd="/sbin/md5"
    fi

    md5_colors="$( get_md5_checksum "${colors}" )"
    if [ ! -f "${status_colors}" ]; then
        /usr/bin/printf "%s" "${md5_colors}" > "${status_colors}"
        return
    fi

    if [ "$( cat "${status_colors}" )" != "${md5_colors}" ]; then
        change_colors
    fi

    check_feeds
}


main() {

        if [ -z "$1" ]; then
            if [ -f "${file_lock}" ]; then
                print_msg warning "Downloading news/podcasts. Wait a moment please!"
                exit 0
            fi

            status_line="$(awk '$1 !~ /^0/ {print $0; exit 0}' "${status_file}")"

            if [ -z "${status_line}" ]; then
                news_number="$(cut -f 2-4 "${status_file}" | \
                    awk '{if ($2 == 1 && $3 == 0) {total=total+$1}} END {print total}')"
                if [ -z "${news_number}" ]; then
                    if [ "${quiet_mode}" != "yes" ]; then
                        echo "-- no news or no (regular) feeds selected --"
                    fi
                else
                    print_msg warning "Downloading news/podcasts feeds"
                    download_feeds
                fi
                exit 0
            fi

            parse_status_line "${status_line}"

            if [ ! -f "${filename}" ]; then
                print_msg warning "Downloading news/podcasts feeds"
                download_feeds
                exit 0
            fi

            news_line="$(sed -n -e "${news_index}p" "${filename}")"
            parse_news_line "${news_line}"

            output="${news_title}"

            if [ "${use_colors}" = "yes" ]; then
                if [ "${breaking_news}" = "1" ]; then
                    output="%{u${color}}%{+u}%{F${color}}${output}%{F- -u-}"
                else
                    output="%{F${color}}${output}%{F-}"
                fi
            fi

            # update status file
            new_index=$((news_index - 1))
            sed -i.bak -e "/${filename##*/}/s/^${news_index}/${new_index}/1" "${status_file}"

            # save news URL
            /usr/bin/printf "%s" "${news_line}" > "${news_url}"

            # show news on the bar
            /usr/bin/printf "%s" "${output}"
            exit 0
        elif [ "$1" = "open" ] || [ "$1" = "url" ]; then
            parse_news_line "$(cat "${news_url}")"
            exec "${open_cmd}" "${url}"
        elif [ "$1" = "search" ] || [ "$1" = "show_menu" ]; then
            search
            exit 0
        elif [ "$1" = "download" ]; then
            print_msg warning "Downloading news/podcasts feeds"
            download_feeds
            exit 0
        elif [ "$1" = "select" ]; then
            select_feeds
            exit 0
        fi
}


setup

main "${1}"

# vim: expandtab shiftwidth=4 smartindent softtabstop=4 tabstop=4
