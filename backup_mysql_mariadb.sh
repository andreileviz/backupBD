#!/bin/bash

source /root/staybox/scripts/config.cfg

# Variáveis
dia=$(date +%d%m%Y)
hora=$(date +%H%M)
db_servidor="$db_servidor"
db_user="$db_user"
retencao="$retencao"
db_pass="$db_pass"

calcular_tamanho_dump() {
    local db="$1"
    local db_servidor="$2"
    local db_user="$3"

    local tamanho_dump
    local tamanho_disponivel
    local tamanho_margem=1024


    tamanho_dump=$(mysql -h "$db_servidor" -u "$db_user" -p"$db_pass" -D "$db" -sse "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.tables WHERE table_schema = '$db';" | tr -d '[:space:]')
    tamanho_dump_int=$(echo "$tamanho_dump" | awk '{print int($1+0.5)}')
    tamanho_disponivel=$(df -m --output=avail $path_backup | tail -n 1 | cut -d\  -f 2)
    tamanho_total=$(( $tamanho_dump_int+$tamanho_margem ))

    if [ $tamanho_total -gt $tamanho_disponivel ]; then
        zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -k "status.$db" -o "Espaço insuficiente para $db"
        echo "0"      
    else
        echo "1"
    fi
}

mkdir -vp $path_backup

for db in $base_dados; do
    resultado=$(calcular_tamanho_dump "$db" "$db_servidor" "$db_user")
    if  [ "$resultado" -eq 1 ]; then
        # Cria os diretórios de backup caso não existam
        mkdir -p "$path_backup/$db/atual"
        mkdir -p "$path_backup/$db/versoes"

        # Caminhos do backup
        backup_path_atual="$path_backup/$db/atual"
        backup_path_versoes="$path_backup/$db/versoes"
        backup_file="$backup_path_atual/$db-$dia-$hora"
        log_file="$backup_path_atual/$db-$dia-$hora.log" # Define o nome do arquivo de log

        # Remove backups baseados na quantidade de dias definida na variável retencao
        find "$backup_path_versoes" -type f -mtime +$retencao -exec rm {} \;

        # Acessa o diretório de backups atual
        cd "$backup_path_atual"

        # Move os backups antigos para o diretório versoes e remove os logs associados
        mv *.sql.gz "$backup_path_versoes" 2>/dev/null
        rm *.log 2>/dev/null

        # Realiza o dump do MySQL/MariaDB e compacta o arquivo SQL em gzip diretamente
        # Redireciona a saída de erro para o arquivo de log
        mysqldump -h "$db_servidor" -u "$db_user" -p"$db_pass" "$db" 2> "$log_file" | gzip > "$backup_file.sql.gz"
        wait


        # Verifica se ocorreram erros e notifica o usuário
        if [ $? -ne 0 ]; then
            if command -v zabbix_sender &> /dev/null; then
                zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -k "status.$db" -o "$db"
            fi
            echo "Ocorreu um erro durante o backup da base $db. Verifique o arquivo de log em $log_file."
        else
            if command -v zabbix_sender &> /dev/null; then
                zabbix_sender -c /etc/zabbix/zabbix_agent2.conf -k "status.$db" -o "0"
            fi
            echo "Backup da base $db do dia ${dia:0:2}/${dia:2:2}/${dia:4:4} às ${hora:0:2}:${hora:2:2} concluído."
        fi
    fi
done
