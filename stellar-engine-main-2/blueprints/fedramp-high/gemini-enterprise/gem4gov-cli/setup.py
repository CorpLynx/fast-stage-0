from setuptools import setup, find_packages

setup(
    name='gem4gov',
    version='0.1.0',
    py_modules=['gem4gov', 'data_stores', 'auth'],
    include_package_data=True,
    install_requires=[
        'click',
        'google-api-python-client',
        'google-auth',
        'google-auth-oauthlib',
        'PyYAML'
    ],
    entry_points={
        'console_scripts': [
            'gem4gov = gem4gov:cli',
        ],
    },
)
