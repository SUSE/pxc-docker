FROM opensuse/leap:15.1 AS build

WORKDIR /opt
RUN mkdir /opt/rootfs

RUN zypper -n in tar gzip hostname libaio1 libnuma1 cmake git gcc gcc-c++ \
	libaio-devel boost-devel openssl-devel ncurses-devel readline-devel \
	curl-devel bison socat scons check-devel libboost_program_options1_66_0-devel \
	curl patch libgcrypt-devel libev-devel

# Build Percona XtraDB Cluster
RUN curl -o source.tar.gz https://www.percona.com/downloads/Percona-XtraDB-Cluster-LATEST/Percona-XtraDB-Cluster-5.7.28-31.41/source/tarball/Percona-XtraDB-Cluster-5.7.28-31.41.tar.gz && \
	tar xf /opt/source.tar.gz && \
	cd Percona-XtraDB-Cluster-5.7.28-31.41 && \
	cmake . \
		-DBUILD_CONFIG=mysql_release \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_INSTALL_PREFIX=/opt/rootfs \
		-DINSTALL_MYSQLTESTDIR= \
		-DWITH_EMBEDDED_SERVER=OFF \
		-DWITH_INNODB_DISALLOW_WRITES=ON \
		-DWITH_RAPID=OFF \
		-DWITH_READLINE=system \
		-DWITH_ROCKSDB=OFF \
		-DWITH_SCALABILITY_METRICS=ON \
		-DWITH_SSL=system \
		-DDOWNLOAD_BOOST=1 \
		-DWITH_BOOST=libboost \
		-DWITH_TOKUDB=OFF \
		-DWITH_UNIT_TESTS=OFF \
		-DWITH_WSREP=ON \
		-DWITH_ZLIB=system && \
	make -j$(nproc) && \
	make -j$(nproc) install
RUN mkdir -p /opt/rootfs/etc/mysql && cp -r Percona-XtraDB-Cluster-5.7.28-31.41/build-ps/ubuntu/extra/percona-xtradb-cluster.conf.d /opt/rootfs/etc/mysql

# Build galera
COPY SConstruct.patch /opt
RUN cd /opt/Percona-XtraDB-Cluster-*/percona-xtradb-cluster-galera && \
    patch < /opt/SConstruct.patch && \
    HOME=$PWD scons tests=0 && \
    install --mode=0644 -D libgalera_smm.so "/opt/rootfs/usr/lib/galera3/libgalera_smm.so"

# TODO: merge
RUN zypper -n in vim
# Build XtraBackup
RUN curl -o xtrabackup.tar.gz https://www.percona.com/downloads/Percona-XtraBackup-2.4/Percona-XtraBackup-2.4.18/source/tarball/percona-xtrabackup-2.4.18.tar.gz && \
	tar xfv xtrabackup.tar.gz && \
	cd percona-xtrabackup-*/ && \
	mkdir build && \
	cd build && \
	cmake .. \
		-DBUILD_CONFIG=xtrabackup_release \
		-DCMAKE_INSTALL_PREFIX=/opt/rootfs \
		-DINSTALL_MYSQLTESTDIR= \
		-DDOWNLOAD_BOOST=1 \
		-DWITH_BOOST=libboost \
		-DWITH_MAN_PAGES=OFF && \
	make -j$(nproc) && \
	make -j$(nproc) install

# Build runtime container
FROM opensuse/leap:15.1

LABEL name="Percona XtraDB Cluster" \
	release="5.7" \
	vendor="Percona" \
	summary="Percona XtraDB Cluster is an active/active high availability and high scalability open source solution for MySQL clustering" \
	description="Percona XtraDB Cluster is a high availability solution that helps enterprises avoid downtime and outages and meet expected customer experience." \
	maintainer="Percona Development <info@percona.com>"

RUN zypper -n in which socat vim

# create mysql user/group before mysql installation
RUN groupadd -g 1001 mysql \
	&& useradd -u 1001 -r -g 1001 -s /sbin/nologin \
		-c "Default Application User" mysql

RUN mkdir /var/run/mysqld && chown 1001 /var/run/mysqld

RUN mkdir -p /etc/mysql/percona-xtradb-cluster.conf.d/ \
	&& echo '!includedir /etc/mysql/conf.d/' > /etc/mysql/my.cnf \
	&& echo '!includedir /etc/mysql/percona-xtradb-cluster.conf.d/' >> /etc/mysql/my.cnf

COPY dockerdir /
RUN mkdir -p /etc/mysql/conf.d/ /var/log/mysql /var/lib/mysql /docker-entrypoint-initdb.d \
	&& chown -R 1001:1001 /etc/mysql/ /var/log/mysql /var/lib/mysql /docker-entrypoint-initdb.d \
	&& chmod -R g=u /etc/mysql/ /var/log/mysql /var/lib/mysql /docker-entrypoint-initdb.d

COPY --from=build /opt/rootfs /

VOLUME ["/var/lib/mysql", "/var/log/mysql"]

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 3306 4567 4568
CMD ["mysqld"]
RUN zypper -n in hostname libaio libatomic1
