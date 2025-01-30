#!/bin/bash
BASE_DIR="/mnt/Movie"
TMP_DIR="${BASE_DIR}/ffmpeg_tmp"
SERIES_LIST_FILE="$(dirname "$0")/series_list.txt"
STATE_FILE="$(dirname "$0")/conversion_state.log"
LOG_FILE="$(dirname "$0")/conversion.log"
EXCLUDE_DIR="${BASE_DIR}/Films"
IFS=$'\n'

#Создаем временную директорию
mkdir -p "$TMP_DIR"

#Функция для записи логов
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

#Проверка стейта на наличие записи о файле
check_state() {
    grep -Fxq "$1" "$STATE_FILE"
}

#Обновление стейта после успешной перекодировки
update_state() {
    echo "$1" >> "$STATE_FILE"
}

#Проверка наличия файла списка сериалов
if [[ ! -f "$SERIES_LIST_FILE" ]]; then
    log "Файл списка каталогов $SERIES_LIST_FILE не найден."
    exit 1
fi

#Чтение списка каталогов из файла
for file in  $(cat series_list.txt); do
    echo $file
    #Удаление экранирующих символов и лишних пробелов
    clean_path=$(echo $file | sed 's/\\//g')
    FULL_PATH="${clean_path}"

    #Проверяем, что каталог существует и не является исключённым
    if [[ ! -d "$FULL_PATH" || "$FULL_PATH" == "$EXCLUDE_DIR"* ]]; then
        log "Пропуск каталога $FULL_PATH (не существует или исключён)"
        continue
    fi

    #Поиск всех видеофайлов для перекодировки в каталоге
    find "$FULL_PATH" -type f \( -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mp4" \) > ./tmp_files.txt
    for file in $(cat tmp_files.txt); do
        # Проверка, было ли видео уже перекодировано
        if check_state "$file"; then
            log "Пропуск $file (уже перекодировано)"
            continue
        fi

        #Перемещение видео во временную директорию
        filename=$(basename "$file")
        mv "$file" "$TMP_DIR/$filename"
        output_file="${FULL_PATH}/${filename%.*}.mp4"

        #Выполняем перекодировку
        log "Начало перекодировки $file"
        ffmpeg -loglevel error -stats -i "$TMP_DIR/$filename" -map 0:0 -filter:v "scale=iw*2:ih*2" -c:v libx264 -b:v 8500k -profile:v high -level:v 4.1 -threads 12 -map 0:1 -c:a:0 copy -disposition:a:0 default -c:s:0 copy -disposition:s:0 0 -default_mode passthrough "$output_file"

        if [[ $? -eq 0 ]]; then
            log "Успешная перекодировка $file в $output_file"
            update_state "$file"
            update_state "$output_file"
            rm -f "$TMP_DIR/$filename"  #Удаляем исходный файл после успешной перекодировки
        else
            log "Ошибка перекодировки $file"
            mv "$TMP_DIR/$filename" "$file"  #Возвращаем файл, если произошла ошибка
        fi
        sed -i '1d' tmp_files.txt
    done
        sed -i '1d' series_list.txt
done < "$SERIES_LIST_FILE"

#Очистка файла series_list.txt после завершения обработки
#> "$SERIES_LIST_FILE"
log "Процесс завершён"