#!/bin/bash
# (C) 2013 - Jesús Martínez Novo
# Script para guardar una copia del sector de arranque de la 
# partición raíz de linux en una partición accesible de windows
# y usarla como gestor de arranque administrada por el gestor
# de arranque de Windows.
# La idea es ponerla en el script de cierre del sistema
# por si cambia, dado que con el GRUB2 si se hacen cambios
# el sector de arranque anterior no permite arrancar el sistema :S


# Directorio donde se guardan las imagenes del sector 0
IMAGEPATH='/usr/share/bootsect-images'
# Directorio temporal donde se copian la imagen del sector 0 extraida del disco
TMPIMAGEPATH='/tmp'
# Dispositivo (partición) del que extraer el sector 0
IMAGEDEV='/dev/sda3'
# Dispositivo donde almacenar la imagen del sector
STOREDEV='/dev/sdb1'
# Ruta completa al archivo del dispositivo donde almacenar la imagen del sector (desde la raíz del dispositivo, no la raíz del sistema+punto de montaje)
STOREFILE='/susebootsect.bin'
# Punto de montaje donde montar el dispositivo (STOREDEV) para copiar la imagen, si no se encuentra montado ya
TMPSTOREMOUNT='/mnt/tmpmount_bsstore'


# Extrae del disco la imagen del primer sector
s_extrae_temp() {
  echo "Creando copia de imagen en ${TMPFILENAME}"
  dd if=${IMAGEDEV} of=${TMPFILENAME} bs=512 count=1 status=noxfer 2>/dev/null
  if [ $? != 0 ]; then
    echo "Error al obtener imagen desde ${IMAGEDEV} en ${TMPFILENAME}."
    return 1
  fi
  return 0
}

s_monta_win_copia() {
  DELETETMPMOUNT=0
  DESMONTAR=0
  RET=0
  read -a TMPSTOREMOUNT <<< `cat /etc/mtab | grep -e "^${STOREDEV}"`
  if [ -z ${TMPSTOREMOUNT[1]} ]; then
    # No está montado
    echo "El dispositivo ${STOREDEV} no está montado. Montando en ${TMPSTOREMOUNT}..."
    if [ ! -d ${TMPSTOREMOUNT} ]; then
      mkdir ${TMPSTOREMOUNT}
      DELETETMPMOUNT=1
    fi
    mount ${STOREDEV} ${TMPSTOREMOUNT} -o rw
    RET=$?
    if [ ${RET} != 0 ]; then
      echo "Error montando ${TMPSTOREMOUNT[0]} en ${TMPSTOREMOUNT[1]}"
    else
      DESMONTAR=1
    fi
  else
    # Está montado como solo lectura?
    MNTRW=`echo ",${TMPSTOREMOUNT[3]}," | grep ",rw,"`
    if [ -z ${MNTRW} ]; then
      echo "El dispositivo ${STOREDEV} está montado como solo lectura. Remontando como LE"
      mount ${TMPSTOREMOUNT[0]} ${TMPSTOREMOUNT[1]} -o remount,rw
      RET=$?
      if [ ${RET} != 0 ]; then
	echo "Error remontando ${TMPSTOREMOUNT[0]} en ${TMPSTOREMOUNT[1]} modo LE"
      fi
    fi
  fi
  if [ ${RET} == 0 ]; then
    # El directorio está montado. Ahora a guardar
    echo "Copiando imagen ${TMPFILENAME} a ${TMPSTOREMOUNT[1]}${STOREFILE}"
    cp ${TMPFILENAME} ${TMPSTOREMOUNT[1]}${STOREFILE}
    RET=$?
    if [ ${RET} != 0 ]; then
      echo "Error al copiar la imagen temporal ${TMPFILENAME} al destino ${TMPSTOREMOUNT[1]}${STOREFILE}"
    fi
  fi
  if [ ${DESMONTAR} == 1 ]; then
    echo "Desmontando ${STOREDEV}"
    umount ${STOREDEV} ${TMPSTOREMOUNT}
    if [ ${DELETETMPMOUNT} == 1 ]; then
      rm -r ${TMPSTOREMOUNT}
    fi
  fi
  return ${RET}
}

s_copia_en_imagenes() {
  APPEND=`date "+%Y%m%d%H%m%S"`
  echo "Copiando imagen al archivo de imágenes"
  cp "${TMPFILENAME}" "${IMAGEPATH}/image_${APPEND}"
  if [ $? != 0 ]; then
      echo "Error al copiar la imagen temporal ${TMPFILENAME} al destino ${IMAGEPATH}/image_${APPEND}"
      return 0
  fi
  return 1
}

s_actualiza_nuevo_bootsect() {
  s_monta_win_copia && s_copia_en_imagenes
  return $?
}

s_main() {
  RET=0
  COPIARSECT=0
  # Obtener archivo temporal
  TMPFILENAME=`dd if=/dev/random bs=8 count=1 status=noxfer 2>/dev/null | hexdump -e '1/8 "%x\n"'`
  TMPFILENAME="${TMPIMAGEPATH}/bootsect-${TMPFILENAME}.bin"
  
  # Extrae la image creando el archivo temporal
  s_extrae_temp
  if [ $? != 0 ]; then
    return 1;
  fi
  
  LASTSAVEDIMAGE=`ls -1 --sort=t --reverse ${IMAGEPATH} | tail -n 1`
  if [ -z ${LASTSAVEDIMAGE} ]; then
    echo "No hay imagen anterior guardada. Se va a realizar la actualización."
    COPIARSECT=1
  else
    diff -q ${TMPFILENAME} ${IMAGEPATH}/${LASTSAVEDIMAGE}
    if [ $? == 1 ]; then
      echo "El sector de arranque ha cambiado. Se va a realizar la actualización."
      COPIARSECT=1
    else
      echo "El sector de arranque no ha cambiado. Está correcto."
    fi
  fi
  
  if [ ${COPIARSECT} == 1 ]; then
    s_actualiza_nuevo_bootsect
    RET=$?
  fi
  
  echo "Borrando archivo temporal ${TMPFILENAME}"
  rm ${TMPFILENAME}
  
  echo "Finalizado"
  return ${RET}
}


s_main
exit $?
