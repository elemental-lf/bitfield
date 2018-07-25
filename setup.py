#!/usr/bin/env python
from distutils.core import setup
from distutils.extension import Extension
try:
    from pip import main as pipmain
except:
    from pip._internal import main as pipmain

VERSION = '0.1.1'

pipmain(['install', 'Cython>=0.28.4'])

from Cython.Build import build_ext

setup(
    name='sparsebitfield',
    version=VERSION,
    license='BSD',
    description='A Cython fast compressed number set',
    author='Steve Stagg, Lars Fenneberg',
    author_email='stestagg@gmail.com, lf@elemental.net',
    url='http://github.com/elemental-lf/sparsebitfield',
    classifiers=[
        'Development Status :: 4 - Beta',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: BSD License',
        'Operating System :: OS Independent',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
    ],
    install_requires=[
        'sortedcontainers>=2.0.4',
    ],
    extentions=[
        Extension('sparsebitfield', ['cimpl/field.pyx'], depends=['cimpl/field.h', 'cimpl/field.c', 'popcount.h'])
    ],
    cmdclass={'build_ext': build_ext},
)
