# Copyright 2007-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=6

inherit autotools linux-info pam systemd toolchain-funcs user

DESCRIPTION="Opensourced tools for VMware guests"
HOMEPAGE="https://github.com/vmware/open-vm-tools"
MY_P="${P}-12406962"
SRC_URI="https://github.com/vmware/open-vm-tools/releases/download/stable-${PV}/${MY_P}.tar.gz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="amd64 ~x86"
IUSE="X +deploypkg +dnet doc +fuse +grabbitmqproxy gtkmm +icu multimon pam +resolutionkms +ssl static-libs +vgauth"
REQUIRED_USE="
	multimon? ( X )
	vgauth? ( ssl )
	grabbitmqproxy? ( ssl )
"

RDEPEND="
	dev-libs/glib
	net-libs/libtirpc
	deploypkg? ( dev-libs/libmspack )
	fuse? ( sys-fs/fuse:0 )
	pam? ( virtual/pam )
	ssl? ( dev-libs/openssl:0 )
	vgauth? (
		dev-libs/libxml2
		dev-libs/xmlsec
	)
	X? (
		x11-libs/libXext
		multimon? ( x11-libs/libXinerama )
		x11-libs/libXi
		x11-libs/libXrender
		x11-libs/libXrandr
		x11-libs/libXtst
		x11-libs/libSM
		x11-libs/libXcomposite
		x11-libs/gdk-pixbuf:2
		x11-libs/gtk+:3
		gtkmm? (
			dev-cpp/gtkmm:3.0
			dev-libs/libsigc++:2
		)
	)
	dnet? ( dev-libs/libdnet )
	icu? ( dev-libs/icu:= )
	resolutionkms? (
		x11-libs/libdrm[video_cards_vmware]
		virtual/libudev
	)
"

DEPEND="${RDEPEND}
	net-libs/rpcsvc-proto
"

BDEPEND="
	virtual/pkgconfig
	doc? ( app-doc/doxygen )
"

S="${WORKDIR}/${MY_P}"

PATCHES=(
	"${FILESDIR}/10.1.0-mount.vmhgfs.patch"
	"${FILESDIR}/10.1.0-Werror.patch"
)

AM_OPTS="-i"

pkg_setup() {
	local CONFIG_CHECK="~VMWARE_BALLOON ~VMWARE_PVSCSI ~VMXNET3"
	use X && CONFIG_CHECK+=" ~DRM_VMWGFX"
	kernel_is -lt 3 9 || CONFIG_CHECK+=" ~VMWARE_VMCI ~VMWARE_VMCI_VSOCKETS"
	kernel_is -lt 3 || CONFIG_CHECK+=" ~FUSE_FS"
	linux-info_pkg_setup
}

src_prepare() {
	eapply -p2 "${PATCHES[@]}"
	eapply_user
	eautoreconf
}

src_configure() {
	local myeconfargs=(
		--without-root-privileges
    --without-kernel-modules
		$(use_enable multimon)
		$(use_with X x)
		$(use_with X gtk3)
		$(use_with gtkmm gtkmm3)
		$(use_enable doc docs)
		--disable-tests
		$(use_enable resolutionkms)
		$(use_enable static-libs static)
		$(use_enable deploypkg)
		$(use_enable grabbitmqproxy)
		$(use_with pam)
		$(use_enable vgauth)
		--disable-caf
		$(use_with dnet)
		$(use_with icu)
	)
	# Avoid a bug in configure.ac
	use ssl || myeconfargs+=( --without-ssl )

	econf "${myeconfargs[@]}"
}

src_install() {
	default
	find "${ED}" -name '*.la' -delete || die

	if use pam; then
		rm "${ED}"/etc/pam.d/vmtoolsd || die
		pamd_mimic_system vmtoolsd auth account
	fi

	newinitd "${FILESDIR}/open-vm-tools.initd" vmware-tools
	newconfd "${FILESDIR}/open-vm-tools.confd" vmware-tools

    insinto /etc/init
	if use vgauth; then
		systemd_newunit "${FILESDIR}"/vmtoolsd.vgauth.service vmtoolsd.service
		systemd_dounit "${FILESDIR}"/vgauthd.service
        doins ${FILESDIR}/vm-vgauth.conf
        newins ${FILESDIR}/vgauth-open-vm-tools.conf open-vm-tools.conf
	else
		systemd_dounit "${FILESDIR}"/vmtoolsd.service
        doins ${FILESDIR}/open-vm-tools.conf
	fi
    doins ${FILESDIR}/mount-vmware-share.conf
	# Replace mount.vmhgfs with a wrapper
	mv "${ED}"/usr/sbin/{mount.vmhgfs,hgfsmounter} || die
	dosbin "${FILESDIR}/mount.vmhgfs"

	# Make fstype = vmhgfs-fuse work in fstab
	dosym vmhgfs-fuse /usr/bin/mount.vmhgfs-fuse

	if use X; then
		fperms 4711 /usr/bin/vmware-user-suid-wrapper
		dobin scripts/common/vmware-xdg-detect-de

		elog "To be able to use the drag'n'drop feature of VMware for file"
		elog "exchange, please add the users to the 'vmware' group."
	fi
}

pkg_postinst() {
	enewgroup vmware
}
