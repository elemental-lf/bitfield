#!/usr/bin/env python

from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext


VERSION = "0.1.0"


ext_modules = [
    Extension("sparsebitfield",
              ["cimpl/field.pyx"],
              depends=["cimpl/field.h", "cimpl/field.c"]
              )
]

if __name__ == "__main__":
    setup(
        name="sparsebitfield",
        version=VERSION,
        license="BSD",

        description="A Cython fast compressed number set",
        author="Steve Stagg, Lars Fenneberg",
        author_email="stestagg@gmail.com, lf@elemental.net",

        url="http://github.com/elemental-lf/sparsebitfield",

        classifiers=[
            'Development Status :: 4 - Beta',
            'Intended Audience :: Developers',
            'License :: OSI Approved :: BSD License',
            'Operating System :: OS Independent',
            'Programming Language :: Python',
            'Programming Language :: Python :: 3',
        ],

        package_data={"Cython": ["cimpl/*.pyx"]},

        cmdclass={"build_ext": build_ext},
        ext_modules=ext_modules,
        
        install_requires=[
        'sortedcontainers>=2.0.4',
        ],        
    )
