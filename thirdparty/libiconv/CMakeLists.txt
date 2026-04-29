list(APPEND CFG_CMD COMMAND env)
if(IOS)
    list(APPEND CFG_CMD
        ac_cv_type_gid_t=yes
        ac_cv_type_uid_t=yes
        ac_cv_type_nlink_t=yes
    )
endif()
append_autotools_vars(CFG_CMD)
list(APPEND CFG_CMD
    ${SOURCE_DIR}/configure --host=${CHOST} --prefix=/
    --enable-shared=false --enable-static=true
    --disable-nls
    --with-threads=none
)

if(IOS)
    list(APPEND BUILD_CMD
        COMMAND make lib/localcharset.h
        COMMAND make -C lib
    )
else()
    list(APPEND BUILD_CMD COMMAND make)
endif()

if(IOS)
    list(APPEND INSTALL_CMD
        COMMAND make -C lib libdir=${STAGING_DIR}/lib includedir=${STAGING_DIR}/include install-lib
        COMMAND mkdir -p ${STAGING_DIR}/include
        COMMAND cp include/iconv.h.inst ${STAGING_DIR}/include/iconv.h
        COMMAND cp lib/libcharset.h ${STAGING_DIR}/include/libcharset.h
        COMMAND cp lib/localcharset.h ${STAGING_DIR}/include/localcharset.h
    )
else()
    list(APPEND INSTALL_CMD COMMAND make DESTDIR=${STAGING_DIR} install)
endif()
# Get rid of libtool crap…
list(APPEND INSTALL_CMD COMMAND rm -f ${STAGING_DIR}/lib/libiconv.la ${STAGING_DIR}/lib/libcharset.la)

external_project(
    DOWNLOAD URL ace8b5f2db42f7b3b3057585e80d9808
    http://ftpmirror.gnu.org/libiconv/libiconv-1.15.tar.gz
    https://ftp.wayne.edu/gnu/libiconv/libiconv-1.15.tar.gz
    http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.15.tar.gz
    CONFIGURE_COMMAND ${CFG_CMD}
    BUILD_COMMAND ${BUILD_CMD}
    INSTALL_COMMAND ${INSTALL_CMD}
)
