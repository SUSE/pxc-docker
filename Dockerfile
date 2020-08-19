FROM registry.suse.com/suse/sle15:15.1 AS build

ARG PXC_VERSION=5.7.30-31.43
ARG XTRABACKUP_VERSION=2.4.20

WORKDIR /opt
RUN mkdir /opt/rootfs
RUN zypper -n rm  container-suseconnect && zypper -n  ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15:/GA/standard/SUSE:SLE-15:GA.repo && zypper -n  ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15:/Update/standard/SUSE:SLE-15:Update.repo && zypper -n  ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/GA/standard/SUSE:SLE-15-SP1:GA.repo && zypper -n  ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update/standard/SUSE:SLE-15-SP1:Update.repo

RUN zypper -n in tar gzip hostname libaio1 libnuma1 cmake git gcc gcc-c++ \
	libaio-devel boost-devel openssl-devel ncurses-devel readline-devel \
	curl-devel bison socat scons check-devel libboost_program_options1_66_0-devel \
	curl patch libgcrypt-devel libev-devel vim

# Build Percona XtraDB Cluster
RUN curl -o source.tar.gz https://kubecf-sources.s3.amazonaws.com/pxc/Percona-XtraDB-Cluster-${PXC_VERSION}.tar.gz && \
	tar xf /opt/source.tar.gz --strip-components=1 && \
	cmake . \
		-DBUILD_CONFIG=mysql_release \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_INSTALL_PREFIX=/usr \
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
	DESTDIR=/opt/rootfs make -j$(nproc) install
RUN mkdir -p /opt/rootfs/etc/mysql && cp -r build-ps/ubuntu/extra/percona-xtradb-cluster.conf.d /opt/rootfs/etc/mysql

# Build galera
RUN cd percona-xtradb-cluster-galera && \
    HOME=$PWD scons tests=0 && \
    install --mode=0644 -D libgalera_smm.so "/opt/rootfs/usr/lib/galera3/libgalera_smm.so"

# Build XtraBackup
RUN curl -o xtrabackup.tar.gz https://kubecf-sources.s3.amazonaws.com/pxc/percona-xtrabackup-${XTRABACKUP_VERSION}.tar.gz && \
	tar xfv xtrabackup.tar.gz && \
	cd percona-xtrabackup-*/ && \
	mkdir build && \
	cd build && \
	cmake .. \
		-DBUILD_CONFIG=xtrabackup_release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DINSTALL_MYSQLTESTDIR= \
		-DDOWNLOAD_BOOST=1 \
		-DWITH_BOOST=libboost \
		-DWITH_MAN_PAGES=OFF && \
	make -j$(nproc) && \
	DESTDIR=/opt/rootfs make -j$(nproc) install

# Build runtime container
FROM registry.suse.com/suse/sle15:15.1
RUN zypper -n rm  container-suseconnect && zypper -n  ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15:/GA/standard/SUSE:SLE-15:GA.repo && zypper -n ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15:/Update/standard/SUSE:SLE-15:Update.repo && zypper -n  ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/GA/standard/SUSE:SLE-15-SP1:GA.repo && zypper -n  ar --refresh http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update/standard/SUSE:SLE-15-SP1:Update.repo

LABEL name="Percona XtraDB Cluster" \
	release="5.7" \
	vendor="Percona" \
	summary="Percona XtraDB Cluster is an active/active high availability and high scalability open source solution for MySQL clustering" \
	description="Percona XtraDB Cluster is a high availability solution that helps enterprises avoid downtime and outages and meet expected customer experience." \
	maintainer="Percona Development <info@percona.com>"

RUN zypper -n in which socat vim hostname libaio libatomic1 awk

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
RUN zypper -n rr -a
